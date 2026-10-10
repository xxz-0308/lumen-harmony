import { image } from '@kit.ImageKit';
import { promptAction } from '@kit.ArkUI';
import { RoomModel, ScCard } from '../room/RoomModel';
import { VideoLayer } from '../room/VideoLayer';
import {
  ChatList,
  DanmakuSettingsPanel,
  LiveFollowList,
  OptionList,
  RoomInfo,
  ScCardView,
  SideChatOverlay
} from '../room/RoomPanels';
import { LiveRouteParam, Nav } from '../app/Nav';
import { AppEnv } from '../app/AppEnv';
import { LeaveBehavior, Settings } from '../app/Settings';
import { MediaVolume } from '../platform/MediaVolume';
import { FollowItem, FollowStore } from '../app/Stores';
import { PlayState } from '../player/LivePlayer';
import { C, formatDuration, formatOnline, Motion, Radius } from '../theme/Theme';
import { Avatar, IconButton, Segmented, SiteBadge } from '../components/Basics';
import { AmbientGlow } from '../components/Decor';
import { BackgroundAudio } from '../platform/BackgroundAudio';
import { LivePip } from '../platform/LivePip';
import { Log } from '../util/Log';
import { isNarrowTheater, showTheaterPanel } from '../room/TheaterLayout';

type SheetKind = '' | 'quality' | 'line' | 'danmaku' | 'follows' | 'sleep';

const INFO_H: number = 84;
const GAP: number = 20;

@ComponentV2
export struct LiveRoomPage {
  @Param route: LiveRouteParam = new LiveRouteParam();
  @Local model: RoomModel = new RoomModel();
  @Local env: AppEnv = AppEnv.inst;
  @Local settings: Settings = Settings.inst;
  @Local danmakuEnabled: boolean = Settings.inst.danmakuOn;
  @Local sideChatEnabled: boolean = Settings.inst.sideChat;
  @Local fillVideo: boolean = Settings.inst.videoFill;
  @Local followed: boolean = false;
  @Local danmakuStyleVersion: number = 0;
  @Local fullscreen: boolean = false;
  @Local panelOpen: boolean = Settings.inst.theaterPanelOpen;
  @Local drawerOpen: boolean = false;
  /**
   * The side panel stays in the tree only while shown or fading out. A transparent panel still
   * hit-tests its children, and once the video widens the info-row sidebar and fullscreen buttons
   * sit underneath it: they stopped responding and the saved "collapsed" state could not be undone.
   */
  @Local panelPresent: boolean = Settings.inst.theaterPanelOpen;
  private panelHideTimer: number = -1;
  @Local panelTab: number = 0;
  @Local controls: boolean = true;
  @Local qualityText: string = '清晰度';
  @Local lineText: string = '线路 1';
  @Local sheet: SheetKind = '';
  /** Where the control that opened a floating option card was touched (window vp). */
  private sheetAnchorX: number = 0;
  private sheetAnchorY: number = 0;
  @Local rootW: number = AppEnv.inst.winWidth;
  @Local rootH: number = AppEnv.inst.winHeight;
  @Local hud: string = '';
  @Local hudValue: number = 0;
  @Local scToast: ScCard | null = null;
  private sourceRoomKey: string = '';
  @Local exiting: boolean = false;
  private disposed: boolean = false;
  @Local exitOpacity: number = 1;
  /**
   * Enter/exit: the page background and the room's chrome fade separately while a copy of the
   * card cover morphs between the card's rect and the player slot. Only an image moves; the
   * native video surface is never transformed.
   */
  @Local bgFade: number = 1;
  @Local chromeFade: number = 1;
  @Local roomTransitioning: boolean = false;
  @Local morphOn: boolean = false;
  @Local morphX: number = 0;
  @Local morphY: number = 0;
  @Local morphW: number = 0;
  @Local morphH: number = 0;
  @Local morphScaleX: number = 1;
  @Local morphScaleY: number = 1;
  /** The player's last frame, captured just before leaving; the card cover is the fallback. */
  @Local morphPixel: image.PixelMap | null = null;
  private videoXc: XComponentController | null = null;
  private backIssued: boolean = false;
  private backCaptureTimer: number = -1;
  @Local sleepInput: string = '';
  @Local sleepMinutes: number = 0;
  @Local sleepRemaining: number = 0;
  private hideTimer: number = -1;
  private hudTimer: number = -1;
  private scTimer: number = -1;
  private sleepTimer: number = -1;
  @Local sleepDeadline: number = 0;
  @Local sleepExpired: boolean = false;
  private sleepPopIssued: boolean = false;
  private sleepNoticeShown: boolean = false;
  private panStart: number = 0;
  private panSide: string = '';
  private lastMediaLevel: number = -1;
  private mediaWrite: Promise<boolean> = Promise.resolve(true);
  private mediaIntent: number = 0;
  private pausedByBackground: boolean = false;
  private audioOwner: number = 0;
  private foregroundListener: () => void = () => this.onForeground();
  @Local pipActive: boolean = false;
  private pipSupported: boolean = LivePip.supported();
  /** While going to the background with auto PiP armed, give the PiP window time to appear. */
  private pipGraceTimer: number = -1;
  private pipCloseTimer: number = -1;
  private pip: LivePip = new LivePip({
    play: () => {
      this.pausedByBackground = false;
      this.model.resume();
    },
    pause: () => this.pausePlayback(),
    onActive: (active: boolean, restoring: boolean) => {
      if (this.disposed) return;
      this.clearPipCloseCheck();
      this.pipActive = active;
      if (active && this.pausedByBackground) {
        this.pausedByBackground = false;
        this.model.resume();
      }
      if (!active && !restoring && !this.env.foreground) {
        // The PiP window was closed while the app stays in the background. Opening the app from
        // its icon can also stop PiP just before the foreground event, so check again shortly.
        this.pipCloseTimer = setTimeout(() => {
          this.pipCloseTimer = -1;
          if (!this.disposed && !this.pipActive && !this.env.foreground) {
            this.pauseForBackground();
          }
        }, 500);
      }
    }
  });

  // ---------- lifecycle ----------

  private syncSettings(): void {
    this.danmakuEnabled = this.settings.danmakuOn;
    this.sideChatEnabled = this.settings.sideChat;
    this.fillVideo = this.settings.videoFill;
    this.model.player.setVolume(this.settings.volumeMode === 'app' ? this.settings.appVolume : 1);
    this.danmakuStyleVersion++;
  }

  aboutToAppear(): void {
    if (this.disposed) return;
    this.env.subscribeForeground(this.foregroundListener);
    this.syncSettings();
    // The cover must be available before the destination's first transition frame.
    this.model.preview = this.route.preview;
  }

  onReady(ctx: NavDestinationContext): void {
    if (this.disposed) return;
    const p = ctx.pathInfo.param as LiveRouteParam;
    Log.i('page', `live onReady ${p.siteId} room=${p.roomId}`);
    this.sourceRoomKey = `${p.siteId}_${p.roomId}`;
    this.audioOwner = BackgroundAudio.attach(AppEnv.inst.context, {
      play: () => {
        this.pausedByBackground = false;
        this.model.resume();
      },
      pause: () => this.pausePlayback()
    });
    this.model.open(p.siteId, p.roomId, p.preview);
    if (Settings.inst.autoFullscreen) {
      this.setFullscreen(true, false);
    }
    this.armHide();
  }

  aboutToDisappear(): void {
    this.disposeRoom('component');
  }

  /**
   * Leaving the room. Usually from aboutToDisappear, but a page that once backed a PiP window is
   * cached by the system (navigationId) and is not destroyed when popped, so the destination's
   * willDisappear also ends the room; otherwise it keeps playing, unseen, after Back.
   */
  private disposeRoom(why: string): void {
    if (this.disposed) {
      return;
    }
    Log.i('page', `live dispose by ${why}`);
    this.disposed = true;
    this.env.unsubscribeForeground(this.foregroundListener);
    this.clearPipCloseCheck();
    this.clearBackCapture();
    this.pip.dispose();
    this.videoXc = null;
    this.clearPipGrace();
    BackgroundAudio.detach(this.audioOwner);
    this.model.dispose();
    AppEnv.inst.setKeepScreenOn(false);
    AppEnv.inst.setBrightness(-1);
    if (this.fullscreen) {
      AppEnv.inst.setImmersive(false);
      AppEnv.inst.setLandscape(false);
    }
    clearTimeout(this.hideTimer);
    clearTimeout(this.panelHideTimer);
    clearTimeout(this.hudTimer);
    clearTimeout(this.scTimer);
    if (this.sleepTimer >= 0) {
      clearInterval(this.sleepTimer);
      this.sleepTimer = -1;
    }
  }

  private onForeground(): void {
    if (this.disposed) return;
    if (this.sleepExpired) {
      this.finishSleep();
      return;
    }
    if (this.env.foreground && this.sleepDeadline > 0) {
      this.tickSleep();
      if (this.sleepExpired) {
        return;
      }
    }
    if (!this.env.foreground) {
      AppEnv.inst.setKeepScreenOn(false);
      if (this.leaveBehavior === 'pip') {
        this.armPipGrace();
      } else {
        this.pauseForBackground();
      }
    } else {
      this.clearPipGrace();
      this.clearPipCloseCheck();
      if (this.pausedByBackground) {
        this.pausedByBackground = false;
        this.model.resume();
      }
      this.onPlayState();
    }
  }

  private pausePlayback(): void {
    if (this.disposed) return;
    this.model.player.pause();
    // Playback intent changes before native paused arrives; release AVSession/task now.
    this.onPlayState();
  }

  @Monitor('model.player.state', 'settings.leaveBehavior')
  onPlayState(): void {
    if (this.disposed) return;
    const state = this.model.player.state;
    Log.i('page', `play state=${state} foreground=${this.env.foreground} mode=${this.leaveBehavior}`);
    const active = this.model.player.wantsPlayback &&
      (state === PlayState.Playing || state === PlayState.Buffering);
    AppEnv.inst.setKeepScreenOn(this.env.foreground && active);
    BackgroundAudio.setMetadata(this.model.title, this.model.userName, this.audioOwner);
    const leave = this.leaveBehavior;
    // The continuous task follows the room, not transient loading states: it cannot be
    // re-requested from the background after a line switch.
    const alive = !this.sleepExpired && state !== PlayState.Error && state !== PlayState.Idle;
    BackgroundAudio.update(alive && this.model.player.wantsPlayback,
      alive && this.model.player.wantsPlayback, leave !== 'pause', this.audioOwner);
    this.pip.setPlaying(active);
    // Arm auto-PiP while loading too: the Home gesture can arrive before the first frame.
    this.pip.setAutoStart(leave === 'pip' && alive && this.model.player.wantsPlayback);
    if (!this.env.foreground) {
      if (leave === 'pip') {
        this.armPipGrace();
      } else {
        this.pauseForBackground();
      }
    }
    if (state === PlayState.Error) {
      this.controls = true;
    }
  }

  /** The leave behaviour in effect; PiP falls back to pausing on devices without it. */
  get leaveBehavior(): LeaveBehavior {
    const leave = this.settings.leaveBehavior;
    return leave === 'pip' && !this.pipSupported ? 'pause' : leave;
  }

  /** Pauses a stream that must not keep playing while the app is hidden. */
  private pauseForBackground(): void {
    if (this.disposed) return;
    if (this.env.foreground || this.leaveBehavior === 'audio' || this.pipActive) {
      return;
    }
    // Loading/buffering streams would otherwise start playing hidden once prepared.
    const state = this.model.player.state;
    if (this.model.player.wantsPlayback && state !== PlayState.Error && state !== PlayState.Idle) {
      this.model.player.pause();
      this.pausedByBackground = true;
    }
  }

  private armPipGrace(): void {
    if (this.disposed || this.env.foreground || this.pipActive || this.pipGraceTimer >= 0 ||
      !this.model.player.wantsPlayback) {
      return;
    }
    this.pipGraceTimer = setTimeout(() => {
      this.pipGraceTimer = -1;
      if (!this.disposed && !this.env.foreground && !this.pipActive) {
        this.pauseForBackground();
      }
    }, 2000);
  }

  private clearPipGrace(): void {
    if (this.pipGraceTimer >= 0) {
      clearTimeout(this.pipGraceTimer);
      this.pipGraceTimer = -1;
    }
  }

  private clearPipCloseCheck(): void {
    if (this.pipCloseTimer >= 0) {
      clearTimeout(this.pipCloseTimer);
      this.pipCloseTimer = -1;
    }
  }

  private startPip(): void {
    this.pip.start().catch(() => {
      if (!this.disposed) promptAction.showToast({ message: '画中画暂不可用' });
    });
  }

  @Monitor('model.player.videoWidth', 'model.player.videoHeight')
  onVideoSize(): void {
    if (this.disposed) return;
    this.pip.setContentSize(this.model.player.videoWidth, this.model.player.videoHeight);
  }

  @Monitor('model.qualities', 'model.qualityIndex', 'model.lineQualityIds', 'model.player.lineIndex')
  onSelection(): void {
    this.qualityText = this.model.qualityLabel;
    this.lineText = `线路 ${this.model.player.lineIndex + 1}`;
    Log.i('page', `selection quality=${this.model.qualityIndex} line=${this.model.player.lineIndex} label=${this.qualityText}`);
  }

  @Monitor('model.detail')
  onDetail(): void {
    this.followed = this.model.isFollowed;
    BackgroundAudio.setMetadata(this.model.title, this.model.userName, this.audioOwner);
  }

  @Monitor('model.latestSc')
  onSc(): void {
    if (this.disposed) return;
    const sc = this.model.latestSc;
    if (sc === null || !this.fullscreen) {
      return;
    }
    this.scToast = sc;
    clearTimeout(this.scTimer);
    this.scTimer = setTimeout(() => {
      this.scToast = null;
    }, 9000);
  }

  // ---------- geometry ----------

  get panelW(): number {
    if (this.rootW >= 1100) {
      return 372;
    }
    return this.narrow ? Math.min(330, Math.max(0, this.rootW - 24)) : 330;
  }

  /** Narrow windows overlay the panel on the video instead of dropping it. */
  get narrow(): boolean {
    return isNarrowTheater(this.rootW);
  }

  get showPanel(): boolean {
    return showTheaterPanel(this.rootW, this.fullscreen, this.panelOpen, this.drawerOpen);
  }

  @Monitor('panelOpen', 'drawerOpen', 'rootW', 'fullscreen')
  onPanelVisibility(): void {
    if (this.disposed) return;
    if (this.panelHideTimer >= 0) {
      clearTimeout(this.panelHideTimer);
      this.panelHideTimer = -1;
    }
    if (this.showPanel) {
      this.panelPresent = true;
      return;
    }
    // Let the fade/slide-out finish, then drop the panel from hit testing entirely.
    this.panelHideTimer = setTimeout(() => {
      this.panelHideTimer = -1;
      if (!this.showPanel) {
        this.panelPresent = false;
      }
    }, 320);
  }

  get leftW(): number {
    return this.rootW - (this.showPanel && !this.narrow ? this.panelW + 12 : 0);
  }

  get topInset(): number {
    return this.env.statusBarHeight + 12;
  }

  get slotW(): number {
    const maxW = this.leftW - GAP * 2;
    const maxH = this.rootH - this.topInset - INFO_H - 16 - this.env.navBarHeight;
    return Math.max(0, Math.min(maxW, maxH * 16 / 9));
  }

  get slotH(): number {
    return this.slotW * 9 / 16;
  }

  get slotX(): number {
    return GAP + (this.leftW - GAP * 2 - this.slotW) / 2;
  }

  // ---------- behaviour ----------

  private setFullscreen(on: boolean, animated: boolean = true): void {
    if (on === this.fullscreen) {
      return;
    }
    AppEnv.inst.setImmersive(on);
    // Do not feed the resized window's aspect ratio back into orientation. A portrait device
    // would otherwise alternate between landscape and auto rotation on every resize event.
    AppEnv.inst.setLandscape(on);
    if (!on) {
      this.scToast = null;
    }
    if (animated && !this.env.reduceMotion) {
      this.getUIContext().animateTo({ curve: Motion.hero }, () => {
        this.fullscreen = on;
      });
    } else {
      this.fullscreen = on;
    }
    this.showControls();
  }

  private armHide(): void {
    if (this.disposed) return;
    clearTimeout(this.hideTimer);
    this.hideTimer = setTimeout(() => {
      if (this.sheet === '' && this.model.player.state === PlayState.Playing) {
        this.controls = false;
      }
    }, 4000);
  }

  private showControls(): void {
    this.controls = true;
    this.armHide();
  }

  private toggleControls(): void {
    if (this.sheet !== '') {
      this.sheet = '';
      return;
    }
    this.controls = !this.controls;
    if (this.controls) {
      this.armHide();
    }
  }

  private openSheet(kind: SheetKind): void {
    this.getUIContext().animateTo({ curve: Motion.smooth }, () => {
      this.sheet = kind;
    });
    this.controls = true;
    clearTimeout(this.hideTimer);
    if (kind === 'follows') {
      FollowStore.inst.refreshAll();
    }
  }

  private closeSheet(): void {
    this.getUIContext().animateTo({ curve: Motion.smooth }, () => {
      this.sheet = '';
    });
    this.armHide();
  }

  private changeVolume(v: number): void {
    if (this.disposed) return;
    if (this.settings.volumeMode === 'app') {
      this.model.player.setVolume(v);
      this.settings.appVolume = v;
      this.settings.scheduleSave();
      return;
    }
    const level = Math.round(v * 20) / 20;
    if (level === this.lastMediaLevel) {
      return;
    }
    this.lastMediaLevel = level;
    const intent = ++this.mediaIntent;
    const roomKey = `${this.model.siteId}_${this.model.roomId}`;
    // Accepted system-volume writes remain ordered even if their originating page leaves.
    this.mediaWrite = this.mediaWrite.then(() => MediaVolume.write(level)).catch(() => false);
    this.mediaWrite.then((ok: boolean) => {
      if (!ok && !this.disposed && intent === this.mediaIntent &&
        roomKey === `${this.model.siteId}_${this.model.roomId}` && this.settings.volumeMode === 'media') {
        this.settings.volumeMode = 'app';
        this.model.player.setVolume(this.settings.appVolume);
        this.settings.scheduleSave();
        promptAction.showToast({ message: '系统媒体音量不可调，已切回应用音量' });
      }
    });
  }

  private showHud(kind: string, v: number): void {
    if (this.disposed) return;
    this.hud = kind;
    this.hudValue = v;
    clearTimeout(this.hudTimer);
    this.hudTimer = setTimeout(() => {
      this.hud = '';
    }, 900);
  }

  private setSleep(minutes: number): void {
    if (this.disposed) return;
    if (this.sleepTimer >= 0) {
      clearInterval(this.sleepTimer);
      this.sleepTimer = -1;
    }
    this.sleepMinutes = minutes;
    this.sleepDeadline = minutes > 0 ? Date.now() + minutes * 60000 : 0;
    this.sleepRemaining = minutes * 60;
    this.closeSheet();
    if (minutes > 0) {
      this.sleepTimer = setInterval(() => this.tickSleep(), 1000);
    }
  }

  private finishSleep(): void {
    if (this.disposed) return;
    if (!this.sleepPopIssued) {
      this.sleepPopIssued = true;
      Nav.stack.pop();
    }
    if (this.env.foreground && !this.sleepNoticeShown) {
      this.sleepNoticeShown = true;
      promptAction.showToast({ message: '定时关闭：已结束播放' });
    }
  }

  private tickSleep(): void {
    if (this.disposed) return;
    if (this.sleepDeadline === 0 || this.sleepExpired) {
      return;
    }
    this.sleepRemaining = Math.max(0, Math.ceil((this.sleepDeadline - Date.now()) / 1000));
    if (this.sleepRemaining === 0) {
      this.sleepExpired = true;
      if (this.sleepTimer >= 0) {
        clearInterval(this.sleepTimer);
        this.sleepTimer = -1;
      }
      this.clearPipGrace();
      this.pip.dispose();
      BackgroundAudio.detach(this.audioOwner);
      this.model.dispose();
      AppEnv.inst.setKeepScreenOn(false);
      // Remove the destination even when only PiP is visible; never pop it again on resume.
      this.finishSleep();
    }
  }

  get sleepLabel(): string {
    if (this.sleepDeadline === 0 || this.sleepExpired) {
      return '定时';
    }
    const min = Math.floor(this.sleepRemaining / 60);
    const sec = this.sleepRemaining % 60;
    return `${min}:${sec < 10 ? '0' : ''}${sec}`;
  }

  private pickFollow(f: FollowItem): void {
    this.closeSheet();
    if (f.siteId === this.model.siteId && f.roomId === this.model.roomId) {
      return;
    }
    this.followed = true;
    this.model.switchTo(f.siteId, f.roomId, f.toRoomItem());
  }

  private togglePanel(): void {
    const open = !this.showPanel;
    this.getUIContext().animateTo(this.env.reduceMotion ? { duration: 0 } : { curve: Motion.smooth }, () => {
      this.panelOpen = open;
      this.drawerOpen = this.narrow && open;
    });
    // Only this explicit user action writes the preference; resizing/fullscreen never does.
    this.settings.theaterPanelOpen = open;
    this.settings.scheduleSave();
    this.showControls();
  }

  private toggleFollow(): void {
    if (this.model.detail === null) {
      promptAction.showToast({ message: '正在加载房间信息，请稍候' });
      return;
    }
    if (FollowStore.inst.storageError.length > 0) {
      promptAction.showToast({ message: FollowStore.inst.storageError });
      return;
    }
    const followed = this.model.toggleFollow();
    this.followed = followed;
    promptAction.showToast({ message: followed ? `已关注 ${this.model.userName}` : '已取消关注' });
  }

  private goBack(): void {
    if (this.exiting || this.disposed) return;
    this.exiting = true;
    // Shrink the picture the viewer was actually watching, not the stale card thumbnail. The grab
    // is short and bounded; a slow or failed one falls back to the cover.
    this.backCaptureTimer = setTimeout(() => {
      this.backCaptureTimer = -1;
      this.fadeBack();
    }, 150);
    this.captureLastFrame().then(() => {
      this.clearBackCapture();
      this.fadeBack();
    });
  }

  private async captureLastFrame(): Promise<void> {
    const xc = this.videoXc;
    if (xc === null || this.route.coverW <= 0 || this.env.reduceMotion || !this.model.player.firstFrame) {
      return;
    }
    try {
      const rect = xc.getXComponentSurfaceRect();
      const w = Math.round(rect.surfaceWidth ?? 0);
      const h = Math.round(rect.surfaceHeight ?? 0);
      if (w <= 0 || h <= 0) {
        return;
      }
      const pixel = await image.createPixelMapFromSurface(xc.getXComponentSurfaceId(),
        { x: 0, y: 0, size: { width: w, height: h } });
      // A timed-out capture must not replace the image during the return animation.
      if (this.backIssued || this.disposed) {
        pixel.release();
      } else {
        this.morphPixel = pixel;
      }
    } catch (e) {
      Log.w('page', 'last frame capture failed; leaving with the cover');
    }
  }

  private clearBackCapture(): void {
    if (this.backCaptureTimer >= 0) {
      clearTimeout(this.backCaptureTimer);
      this.backCaptureTimer = -1;
    }
  }

  private fadeBack(): void {
    if (this.disposed || this.sleepPopIssued || this.backIssued) return;
    this.backIssued = true;
    // The destination's customTransition morphs the picture back into its card.
    Nav.stack.pop(true);
  }

  /** Where the player sits right now (theater slot, or the whole window in fullscreen). */
  private playerRect(): number[] {
    return this.fullscreen ? [0, 0, this.rootW, this.rootH] :
      [this.slotX, this.topInset, this.slotW, this.slotH];
  }

  /** Decode and cache the overlay at player size once; only render transforms animate. */
  private prepareMorph(r: number[]): void {
    const player = this.playerRect();
    this.morphW = Math.max(1, player[2]);
    this.morphH = Math.max(1, player[3]);
    this.setMorph(r);
    this.morphOn = true;
  }

  private setMorph(r: number[]): void {
    this.morphX = r[0];
    this.morphY = r[1];
    this.morphScaleX = r[2] / this.morphW;
    this.morphScaleY = r[3] / this.morphH;
  }

  private get cardRect(): number[] {
    const p = this.route;
    return [p.coverX, p.coverY, p.coverW, p.coverH];
  }

  private roomTransition(operation: NavigationOperation, isEnter: boolean): NavDestinationTransition[] | undefined {
    const reduce = this.env.reduceMotion;
    const fromCard = this.route.coverW > 0 && !reduce;
    if (isEnter && operation === NavigationOperation.PUSH) {
      this.roomTransitioning = true;
      this.bgFade = 0;
      this.chromeFade = 0;
      if (!fromCard) {
        // No card to morph from: fade only. Scaling the whole page also transforms the native
        // surface and makes the entire room and its glass panels repaint on every frame.
        return [{
          duration: reduce ? 160 : 240,
          curve: Curve.EaseOut,
          event: () => {
            this.bgFade = 1;
            this.chromeFade = 1;
          },
          onTransitionEnd: () => {
            this.roomTransitioning = false;
          }
        }];
      }
      this.prepareMorph(this.cardRect);
      return [{
        duration: 300,
        curve: Curve.Friction,
        event: () => {
          this.setMorph(this.playerRect());
        },
        onTransitionEnd: () => {
          this.morphOn = false;
        }
      }, {
        duration: 200,
        curve: Curve.EaseOut,
        event: () => {
          this.bgFade = 1;
        }
      }, {
        delay: 160,
        duration: 200,
        curve: Curve.EaseOut,
        event: () => {
          this.chromeFade = 1;
        },
        onTransitionEnd: () => {
          this.roomTransitioning = false;
        }
      }];
    }
    if (!isEnter && operation === NavigationOperation.POP) {
      this.roomTransitioning = true;
      const sameRoom = this.sourceRoomKey === `${this.model.siteId}_${this.model.roomId}`;
      if (!fromCard || !sameRoom) {
        return [{
          duration: reduce ? 140 : 200,
          curve: Curve.EaseIn,
          event: () => {
            this.bgFade = 0;
            this.chromeFade = 0;
          },
          onTransitionEnd: () => {
            this.roomTransitioning = false;
            this.morphPixel = null;
          }
        }];
      }
      this.prepareMorph(this.playerRect());
      return [{
        duration: 280,
        curve: Curve.Friction,
        event: () => {
          this.setMorph(this.cardRect);
        },
        onTransitionEnd: () => {
          this.morphOn = false;
          this.morphPixel = null;
        }
      }, {
        duration: 120,
        curve: Curve.EaseIn,
        event: () => {
          this.chromeFade = 0;
        }
      }, {
        delay: 80,
        duration: 200,
        curve: Curve.EaseIn,
        event: () => {
          this.bgFade = 0;
        },
        onTransitionEnd: () => {
          this.roomTransitioning = false;
        }
      }];
    }
    return undefined;
  }

  /** The image that travels between card and player: the card's own cover when we have it. */
  get morphCover(): string {
    const preview = this.route.preview;
    return preview !== null && preview.cover.length > 0 ? preview.cover : this.model.cover;
  }

  private onBack(): boolean {
    if (this.sheet !== '') {
      this.closeSheet();
      return true;
    }
    if (this.fullscreen) {
      this.setFullscreen(false);
      return true;
    }
    this.goBack();
    return true;
  }

  // ---------- builders ----------

  @Builder
  topBar() {
    Row({ space: 12 }) {
      IconButton({ dim: 44,
        icon: $r('sys.symbol.chevron_backward'), glass: true, label: '返回', onTap: () => {
          if (this.fullscreen) {
            this.setFullscreen(false);
          } else {
            this.goBack();
          }
        }
      })
      if (this.fullscreen) {
        Avatar({ src: this.model.avatar, dim: 36 })
        Column({ space: 2 }) {
          Text(this.model.userName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(C.onMedia)
          Text(this.model.title)
            .fontSize(12)
            .fontColor(C.onMedia2)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      } else {
        Blank()
      }
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.flame_fill'))
          .fontSize(13)
          .fontColor(['#FFB27A'])
        Text(formatOnline(this.model.online))
          .fontSize(13)
          .fontColor(C.onMedia)
          .fontFeature('"tnum" on')
      }
      .padding({ left: 10, right: 12, top: 6, bottom: 6 })
      .borderRadius(Radius.pill)
      .backgroundColor('#40000000')
      .backgroundBlurStyle(BlurStyle.Thin)
      if (this.fullscreen) {
        IconButton({ dim: 44,
          icon: this.followed ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
          glass: true, active: this.followed, label: this.followed ? '已关注' : '关注',
          onTap: () => this.toggleFollow()
        })
        IconButton({ dim: 44,
          icon: $r('sys.symbol.person_2'), glass: true, label: '关注直播中',
          onTap: () => this.openSheet('follows')
        })
      }
    }
    .width('100%')
    .padding({
      left: 16, right: 16, top: this.fullscreen ? Math.max(16, this.env.statusBarHeight) : 14, bottom: 28
    })
    .linearGradient({ angle: 180, colors: [['#99000000', 0], ['#00000000', 1]] })
  }

  @Builder
  pill(label: () => string, onTap: () => void) {
    Text(label())
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(C.onMedia)
      .height(44)
      .padding({ left: 16, right: 16 })
      .borderRadius(Radius.pill)
      .backgroundColor('#40000000')
      .backgroundBlurStyle(BlurStyle.Thin)
      .stateStyles({
        normal: { .opacity(1) },
        pressed: { .opacity(0.72) }
      })
      .accessibilityText(label())
      .onClick(() => onTap())
  }

  @Builder
  bottomBar() {
    Row({ space: 10 }) {
      Scroll() {
        this.bottomControls()
      }
      .layoutWeight(1)
      .height(48)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .onScrollStart(() => this.showControls())
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down && e.touches.length > 0) {
          this.sheetAnchorX = e.touches[0].windowX;
          this.sheetAnchorY = e.touches[0].windowY;
        }
      })
      IconButton({ dim: 44,
        icon: this.fullscreen ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') :
          $r('sys.symbol.arrow_up_left_and_arrow_down_right'),
        glass: true, label: this.fullscreen ? '退出全屏' : '全屏', onTap: () => this.setFullscreen(!this.fullscreen)
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 28, bottom: this.fullscreen ? Math.max(16, this.env.navBarHeight + 8) : 12 })
    .linearGradient({ angle: 0, colors: [['#99000000', 0], ['#00000000', 1]] })
  }

  @Builder
  bottomControls() {
    Row({ space: 10 }) {
      IconButton({ dim: 44,
        icon: $r('sys.symbol.arrow_clockwise'), glass: true, label: '刷新', onTap: () => {
          this.model.refresh();
          this.showControls();
        }
      })
      IconButton({ dim: 44,
        icon: this.danmakuEnabled ? $r('sys.symbol.ellipsis_message') : $r('sys.symbol.ellipsis_message_slash'),
        glass: true, active: this.danmakuEnabled, label: this.danmakuEnabled ? '关闭弹幕' : '开启弹幕', onTap: () => {
          this.danmakuEnabled = !this.danmakuEnabled;
          this.settings.danmakuOn = this.danmakuEnabled;
          this.settings.scheduleSave();
          this.showControls();
        }
      })
      IconButton({ dim: 44,
        icon: $r('sys.symbol.slider_horizontal_2'), glass: true, label: '弹幕设置',
        onTap: () => this.openSheet('danmaku')
      })
      this.pill(() => this.sleepLabel, () => this.openSheet('sleep'))
      if (this.pipSupported) {
        IconButton({ dim: 44,
          icon: $r('sys.symbol.rectangle_on_rectangle'), glass: true, label: '画中画',
          onTap: () => this.startPip()
        })
      }
      Blank()
      if (this.model.qualities.length > 0) {
        this.pill(() => this.qualityText, () => this.openSheet('quality'))
      }
      if (this.model.lines.length > 1) {
        this.pill(() => this.lineText, () => this.openSheet('line'))
      }
    }
    .width(Math.max(660, (this.fullscreen ? this.rootW : this.slotW) - 86))
    .height(48)
  }

  @Builder
  hudView() {
    if (this.hud.length > 0) {
      Row({ space: 10 }) {
        SymbolGlyph(this.hud === 'bright' ? $r('sys.symbol.sun_max_fill') : $r('sys.symbol.speaker_wave_3_fill'))
          .fontSize(18)
          .fontColor([Color.White])
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(4)
            .borderRadius(2)
            .backgroundColor('#40FFFFFF')
          Row()
            .width(`${Math.round(this.hudValue * 100)}%`)
            .height(4)
            .borderRadius(2)
            .backgroundColor(Color.White)
        }
        .width(140)
        Text(`${Math.round(this.hudValue * 100)}`)
          .fontSize(13)
          .fontColor(Color.White)
          .width(30)
          .fontFeature('"tnum" on')
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .borderRadius(Radius.pill)
      .backgroundColor('#66000000')
      .backgroundBlurStyle(BlurStyle.Thin)
      .position({ x: '50%', y: this.fullscreen ? 56 : 24 })
      .markAnchor({ x: '50%', y: 0 })
      .hitTestBehavior(HitTestMode.None)
      .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
    }
  }

  @Builder
  videoStage() {
    Stack() {
      VideoLayer({
        model: this.model,
        fill: this.fillVideo,
        danmakuOn: this.danmakuEnabled,
        styleVersion: this.danmakuStyleVersion,
        cornerRadius: this.fullscreen ? 0 : Radius.xl,
        onSurface: (xc: XComponentController) => {
          if (this.disposed) return;
          this.videoXc = xc;
          this.pip.attach(AppEnv.inst.context, xc, Nav.id);
        }
      })

      if (this.fullscreen && this.sideChatEnabled) {
        SideChatOverlay({ model: this.model })
          .width('26%')
          .height('55%')
          .position({ x: '72%', y: '38%' })
          .id('fullscreen_chat_overlay')
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.scToast !== null && this.fullscreen) {
        ScCardView({ card: this.scToast, compact: true })
          .width(280)
          .position({ x: 20, y: Math.max(20, this.env.statusBarHeight) + 70 })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -30 }))
            .animation({ curve: Motion.smooth }))
          .onClick(() => {
            this.scToast = null;
          })
      }

      Column() {
        this.topBar()
        Blank()
        this.bottomBar()
      }
      .width('100%')
      .height('100%')
      .opacity(this.controls ? 1 : 0)
      .translate({ y: this.controls ? 0 : 4 })
      .animation({ duration: 220, curve: Curve.EaseOut })
      .hitTestBehavior(this.controls ? HitTestMode.Default : HitTestMode.None)

      this.hudView()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .id('video_stage')
    .borderRadius(this.fullscreen ? 0 : Radius.xl)
    .clip(true)
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 2 })
          .onAction(() => this.setFullscreen(!this.fullscreen)),
        TapGesture({ count: 1 })
          .onAction(() => this.toggleControls()),
        LongPressGesture({ duration: 450 })
          .onAction(() => this.openSheet('follows')),
        PinchGesture()
          .onActionEnd((e: GestureEvent) => {
            // Designed to behave the same in theater and fullscreen.
            if (e.scale > 1.08 && !this.fillVideo) {
              this.fillVideo = true;
              this.settings.videoFill = true;
              this.settings.scheduleSave();
              promptAction.showToast({ message: '填充屏幕' });
            } else if (e.scale < 0.92 && this.fillVideo) {
              this.fillVideo = false;
              this.settings.videoFill = false;
              this.settings.scheduleSave();
              promptAction.showToast({ message: '完整画面' });
            }
          }),
        PanGesture({ direction: PanDirection.Vertical, distance: 10 })
          .onActionStart((e: GestureEvent) => {
            const x = e.fingerList.length > 0 ? e.fingerList[0].localX : 0;
            const w = this.fullscreen ? this.rootW : this.slotW;
            this.panSide = x < w / 2 ? 'bright' : 'volume';
            Log.i('gesture', `vertical pan side=${this.panSide} fullscreen=${this.fullscreen}`);
            this.panStart = this.panSide === 'bright' ? AppEnv.inst.getBrightness() :
              (this.settings.volumeMode === 'media' ? MediaVolume.read() ?? this.settings.appVolume :
                this.settings.appVolume);
            this.lastMediaLevel = -1;
          })
          .onActionUpdate((e: GestureEvent) => {
            const h = this.fullscreen ? this.rootH : this.slotH;
            const v = Math.max(0, Math.min(1, this.panStart - e.offsetY / (h * 0.75)));
            if (this.panSide === 'bright') {
              AppEnv.inst.setBrightness(v);
            } else {
              this.changeVolume(v);
            }
            this.showHud(this.panSide, v);
          })
      )
    )
  }

  @Builder
  infoBar() {
    Row({ space: 14 }) {
      Avatar({ src: this.model.avatar, dim: 48, live: this.model.detail?.status ?? false })
      Column({ space: 6 }) {
        Text(this.model.title.length > 0 ? this.model.title : this.model.userName)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(this.model.userName)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(C.text2)
          SiteBadge({ siteId: this.model.siteId, onMedia: false })
          if (this.model.area.length > 0) {
            Text(this.model.area)
              .fontSize(12)
              .fontColor(C.text3)
          }
          if ((this.model.detail?.startTime ?? 0) > 0) {
            Text(formatDuration(this.model.detail?.startTime ?? 0))
              .fontSize(12)
              .fontColor(C.text3)
          }
        }
      }
      .width(Math.max(0, this.slotW - 172))
      .alignItems(HorizontalAlign.Start)

    }
    .width(this.slotW)
    .height(INFO_H)
    .position({ x: this.slotX, y: this.topInset + this.slotH })
    .opacity(this.fullscreen ? 0 : 1)
    .translate({ y: this.fullscreen ? 6 : 0 })
    .animation({ duration: 220, curve: Curve.EaseOut })
  }

  @Builder
  theaterActions() {
    Row({ space: 8 }) {
      IconButton({ dim: 44,
        icon: this.followed ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
        active: this.followed, label: this.followed ? '已关注' : '关注',
        onTap: () => this.toggleFollow()
      })
      IconButton({ dim: 44,
        icon: this.showPanel ? $r('sys.symbol.close_sidebar') : $r('sys.symbol.open_sidebar'),
        label: this.showPanel ? '收起弹幕侧栏' : '展开弹幕侧栏',
        onTap: () => this.togglePanel()
      })
    }
    .width(96)
    .height(INFO_H)
    .position({ x: this.slotX + this.slotW - 96, y: this.topInset + this.slotH })
    .visibility(this.fullscreen ? Visibility.None : Visibility.Visible)
  }

  @Builder
  sidePanel() {
    Column() {
      Row() {
        Segmented({
          items: ['弹幕', '关注', '信息'],
          selected: this.panelTab,
          segmentWidth: Math.min(76, Math.max(40, (this.panelW - 60) / 3)),
          onSelect: (i: number) => {
            this.panelTab = i;
            if (i === 1) {
              FollowStore.inst.refreshAll();
            }
          }
        })
        if (this.narrow) {
          IconButton({ dim: 44, icon: $r('sys.symbol.xmark'), label: '收起弹幕侧栏',
            onTap: () => this.togglePanel() })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 14, bottom: 10 })

      Stack() {
        ChatList({ model: this.model, dark: this.env.isDark })
          .visibility(this.panelTab === 0 ? Visibility.Visible : Visibility.Hidden)
        if (this.panelTab === 1) {
          LiveFollowList({
            currentKey: `${this.model.siteId}_${this.model.roomId}`,
            onPick: (f: FollowItem) => this.pickFollow(f)
          })
            .padding({ left: 8, right: 8 })
        }
        if (this.panelTab === 2) {
          RoomInfo({ model: this.model })
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width(this.panelW)
    .id('theater_chat_panel')
    .height(this.rootH - this.topInset - 12 - this.env.navBarHeight)
    .position({ x: this.rootW - this.panelW - 12, y: this.topInset })
    .borderRadius(Radius.xl)
    .backgroundColor(C.glassTint)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .borderWidth(1)
    .borderColor(C.glassStroke)
    .clip(true)
    .renderGroup(this.roomTransitioning)
    .visibility(this.fullscreen || !this.panelPresent ? Visibility.None : Visibility.Visible)
    .opacity(this.showPanel && !this.fullscreen ? 1 : 0)
    .translate({ x: this.showPanel && !this.fullscreen ? 0 : 40 })
    .hitTestBehavior(this.showPanel && !this.fullscreen ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  sheetContent() {
    if (this.sheet === 'quality') {
      OptionList({
        options: this.model.qualities.map((q) => q.name),
        selected: this.model.qualityIndex,
        onPick: (i: number) => {
          this.closeSheet();
          this.model.selectQuality(i);
        }
      })
        .height(Math.min(this.sheetOptionCount * 52, this.sheetCardMaxH - 62))
    } else if (this.sheet === 'line') {
      OptionList({
        options: this.model.lines.map((u: string, i: number) => `线路 ${i + 1}${u.indexOf('.m3u8') >= 0 ? ' · HLS' : ''}`),
        selected: this.model.player.lineIndex,
        onPick: (i: number) => {
          this.closeSheet();
          this.model.selectLine(i);
        }
      })
        .height(Math.min(this.sheetOptionCount * 52, this.sheetCardMaxH - 62))
    } else if (this.sheet === 'danmaku') {
      DanmakuSettingsPanel({ onChange: () => this.syncSettings() })
        .height(Math.max(0, Math.min(560, this.sheetCardMaxH - 62)))
    } else if (this.sheet === 'sleep') {
      Column({ space: 12 }) {
        OptionList({
          options: ['关闭定时', '15 分钟', '30 分钟', '60 分钟', '90 分钟'],
          selected: [0, 15, 30, 60, 90].indexOf(this.sleepMinutes),
          onPick: (i: number) => this.setSleep([0, 15, 30, 60, 90][i])
        })
          .height(5 * 52)
        Row({ space: 10 }) {
          TextInput({ text: this.sleepInput, placeholder: '自定义分钟（1–720）' })
            .type(InputType.Number)
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#26FFFFFF')
            .fontColor(C.onMedia)
            .onChange((value: string) => {
              this.sleepInput = value;
            })
          Button('开始')
            .height(44)
            .backgroundColor(C.accent)
            .onClick(() => {
              const minutes = Number(this.sleepInput);
              if (!/^\d{1,3}$/.test(this.sleepInput) || minutes < 1 || minutes > 720) {
                promptAction.showToast({ message: '请输入 1–720 分钟' });
                return;
              }
              this.setSleep(minutes);
            })
        }
        .padding({ left: 12, right: 12 })
        Text('时间到后结束播放并返回上一页')
          .fontSize(12)
          .fontColor(C.onMedia2)
          .padding({ left: 16 })
      }
      .width('100%')
    } else if (this.sheet === 'follows') {
      LiveFollowList({
        currentKey: `${this.model.siteId}_${this.model.roomId}`,
        onMedia: true,
        onPick: (f: FollowItem) => this.pickFollow(f)
      })
        .padding({ left: 10, right: 10 })
    }
  }

  get sheetTitle(): string {
    switch (this.sheet) {
      case 'quality':
        return '清晰度';
      case 'line':
        return '线路';
      case 'danmaku':
        return '弹幕设置';
      case 'sleep':
        return '定时关闭';
      case 'follows':
        return `关注 · 直播中 ${FollowStore.inst.liveItems.length}`;
      default:
        return '';
    }
  }

  /** Option cards are sized by their content; these are the list-based ones. */
  get sheetOptionCount(): number {
    switch (this.sheet) {
      case 'quality':
        return this.model.qualities.length;
      case 'line':
        return this.model.lines.length;
      default:
        return 0;
    }
  }

  get sheetCardW(): number {
    return Math.min(this.sheet === 'danmaku' ? 380 : 300, Math.max(0, this.rootW - 24));
  }

  /** The card's bottom edge sits just above the touched control. */
  get sheetCardBottom(): number {
    const touched = this.sheetAnchorY > 0 ? this.sheetAnchorY - 30 : this.rootH - 96;
    return Math.max(this.topInset + 160, Math.min(touched, this.rootH - 24));
  }

  get sheetCardMaxH(): number {
    return Math.min(this.rootH * 0.6, this.sheetCardBottom - this.topInset);
  }

  get sheetCardX(): number {
    const w = this.sheetCardW;
    const center = this.sheetAnchorX > 0 ? this.sheetAnchorX : this.rootW / 2;
    return Math.max(12, Math.min(center - w / 2, this.rootW - w - 12));
  }

  get followPanelW(): number {
    return this.narrow ? Math.min(380, Math.max(0, this.rootW - 24)) : Math.min(380, this.rootW * 0.4);
  }

  @Builder
  sheetHeader() {
    Row() {
      Text(this.sheetTitle)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(C.onMedia)
      Blank()
      if (this.sheet === 'follows') {
        IconButton({ dim: 40,
          icon: $r('sys.symbol.arrow_clockwise'), tint: C.onMedia, iconSize: 17, label: '刷新',
          onTap: () => {
            FollowStore.inst.refreshAll(true);
          }
        })
        IconButton({ dim: 40,
          icon: $r('sys.symbol.xmark'), tint: C.onMedia, iconSize: 17, label: '关闭',
          onTap: () => this.closeSheet()
        })
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 18, right: 8 })
  }

  @Builder
  sheetLayer() {
    if (this.sheet !== '') {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#33000000')
          .transition(TransitionEffect.OPACITY)
          .onClick(() => this.closeSheet())
        if (this.sheet === 'follows') {
          // The follow list is long: a full-height side panel, but inset and rounded.
          Column() {
            this.sheetHeader()
            Column() {
              this.sheetContent()
            }
            .layoutWeight(1)
            .width('100%')
          }
          .width(this.followPanelW)
          .height(Math.max(0, this.rootH - this.topInset - 12 - this.env.navBarHeight))
          .position({ x: this.rootW - this.followPanelW - 12, y: this.topInset })
          .borderRadius(Radius.xl)
          .backgroundColor('#A6121216')
          .backgroundBlurStyle(BlurStyle.Thick)
          .borderWidth(1)
          .borderColor('#1FFFFFFF')
          .shadow({ radius: 28, color: '#4D000000', offsetY: 8 })
          .clip(true)
          .transition(TransitionEffect.translate({ x: 60 }).combine(TransitionEffect.OPACITY))
          .gesture(PanGesture({ direction: PanDirection.Right, distance: 30 })
            .onActionEnd(() => this.closeSheet()))
        } else {
          // Floating card above the control that opened it; taps beside it reach the scrim.
          Column() {
            Column() {
              this.sheetHeader()
              this.sheetContent()
            }
            .width(this.sheetCardW)
            .constraintSize({ maxHeight: this.sheetCardMaxH })
            .padding({ bottom: 10 })
            .borderRadius(Radius.xl)
            .backgroundColor('#99121216')
            .backgroundBlurStyle(BlurStyle.Thick)
            .borderWidth(1)
            .borderColor('#24FFFFFF')
            .shadow({ radius: 32, color: '#59000000', offsetY: 10 })
            .clip(true)
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9,
              centerY: '100%' })).animation({ duration: this.env.reduceMotion ? 0 : 220, curve: Motion.snappy }))
          }
          .width(this.sheetCardW)
          .height(this.sheetCardBottom)
          .justifyContent(FlexAlign.End)
          .position({ x: this.sheetCardX, y: 0 })
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // Page background on its own layer: it fades in under the travelling cover.
        Stack() {
          AmbientGlow({ src: this.model.cover, glowHeight: this.rootH, strength: this.fullscreen ? 0 : 0.9 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.fullscreen ? Color.Black : C.bg)
        .opacity(this.bgFade)

        Stack({ alignContent: Alignment.TopStart }) {
        this.infoBar()

        // the video morphs between its theater slot and the full window
        Stack() {
          this.videoStage()
        }
        .width(this.fullscreen ? this.rootW : this.slotW)
        .height(this.fullscreen ? this.rootH : this.slotH)
        .position({ x: this.fullscreen ? 0 : this.slotX, y: this.fullscreen ? 0 : this.topInset })
        .borderRadius(this.fullscreen ? 0 : Radius.xl)
        .shadow(this.fullscreen ? { radius: 0, color: Color.Transparent } :
          { radius: 36, color: '#59000000', offsetY: 14 })

        this.theaterActions()
        this.sidePanel()
        this.sheetLayer()
        }
        .width('100%')
        .height('100%')
        .opacity(this.chromeFade)

        if (this.morphOn) {
          Stack() {
            if (this.morphPixel !== null) {
              Image(this.morphPixel)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            } else {
              // The card has already loaded this cover. Do not run another image fade inside
              // the moving layer: that would invalidate its render cache throughout the morph.
              Image(this.morphCover)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .syncLoad(false)
                .draggable(false)
            }
          }
          .width(this.morphW)
          .height(this.morphH)
          .position({ x: 0, y: 0 })
          .backgroundColor(Color.Black)
          .borderRadius(this.fullscreen ? 0 : Radius.xl)
          .clip(true)
          .renderGroup(true)
          .scale({ x: this.morphScaleX, y: this.morphScaleY, centerX: 0, centerY: 0 })
          .translate({ x: this.morphX, y: this.morphY })
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.exitOpacity)
      .enabled(!this.exiting)
      .onAreaChange((o: Area, n: Area) => {
        if (this.narrow !== isNarrowTheater(n.width as number)) this.drawerOpen = false;
        this.rootW = n.width as number;
        this.rootH = n.height as number;
      })
    }
    .hideTitleBar(true)
    .hideToolBar(true)
    // Transparent: the page below stays visible while this room's background fades in and out.
    .backgroundColor(Color.Transparent)
    .onReady((ctx: NavDestinationContext) => this.onReady(ctx))
    .onBackPressed(() => this.onBack())
    .onWillDisappear(() => this.disposeRoom('navigation'))
    .customTransition((operation: NavigationOperation, isEnter: boolean) => this.roomTransition(operation, isEnter))
  }
}
