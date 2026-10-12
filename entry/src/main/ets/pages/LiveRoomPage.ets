import { image } from '@kit.ImageKit';
import { KeyboardAvoidMode, promptAction, UIContext } from '@kit.ArkUI';
import { RoomModel, ScCard } from '../room/RoomModel';
import { RoomMount } from '../room/RoomMount';
import { VideoLayer } from '../room/VideoLayer';
import {
  ChatList,
  DanmakuSettingsPanel,
  LiveFollowList,
  OptionList,
  OptionChoice,
  RoomInfo,
  ScCardView,
  SideChatOverlay
} from '../room/RoomPanels';
import { LiveRouteParam, Nav } from '../app/Nav';
import { NavigationActivity } from '../app/NavigationActivity';
import { RetainedRoomPlayback } from '../app/RetainedRoomPlayback';
import { RoomBulletDelivery } from '../danmaku/RoomBulletDelivery';
import { DanmakuEngine } from '../danmaku/DanmakuEngine';
import { PipDanmakuController } from '../platform/PipDanmakuController';
import { AppEnv } from '../app/AppEnv';
import { LeaveBehavior, Settings } from '../app/Settings';
import { MediaVolume } from '../platform/MediaVolume';
import { FollowItem, FollowStore } from '../app/Stores';
import { PlayState } from '../player/LivePlayer';
import { C, formatDuration, formatOnline, Motion, Radius, SiteStyle } from '../theme/Theme';
import { Avatar, IconButton, LiveDot } from '../components/Basics';
import { AmbientGlow } from '../components/Decor';
import { BackgroundAudio } from '../platform/BackgroundAudio';
import { LivePip } from '../platform/LivePip';
import { Log } from '../util/Log';
import { PerfTrace } from '../util/PerfTrace';
import { isNarrowTheater, showTheaterPanel } from '../room/TheaterLayout';
import { RoomSheet } from '../room/RoomSheets';
import { layoutRoomSheet, RoomSheetLayout, SheetKind } from '../room/RoomSheetLayout';

const INFO_H: number = 88;
const GAP: number = 28;
const PANEL_TABS: string[] = ['弹幕', '关注', '信息'];

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
  private appliedDanmakuStyle: string = '';
  private appliedVolume: number = -1;
  @Local fullscreen: boolean = false;
  @Local presentationActive: boolean = false;
  @Local surfaceMounted: boolean = false;
  @Local topMounted: boolean = false;
  @Local bottomMounted: boolean = false;
  @Local chromeMounted: boolean = false;
  @Local panelMounted: boolean = false;
  @Local glowMounted: boolean = false;
  private mount: RoomMount = new RoomMount();
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
  private sheetKeyboardContext: UIContext | null = null;
  private previousKeyboardMode: KeyboardAvoidMode | null = null;
  @Local rootW: number = AppEnv.inst.winWidth;
  @Local rootH: number = AppEnv.inst.winHeight;
  @Local hud: string = '';
  @Local hudValue: number = 0;
  @Local scToast: ScCard | null = null;
  private sourceRoomKey: string = '';
  @Local exiting: boolean = false;
  private disposed: boolean = false;
  private readonly playbackOwner: number = RetainedRoomPlayback.newOwner();
  private roomReady: boolean = false;
  private pipHandoff: boolean = false;
  private pipStartRoom: string = '';
  private pipStartTimer: number = -1;
  private fullscreenTarget: boolean = false;
  private fullscreenSeq: number = 0;
  @Local exitOpacity: number = 1;
  /**
   * Enter/exit: the page background and the room's chrome fade separately while a copy of the
   * card cover morphs between the card's rect and the player slot. Only an image moves; the
   * native video surface is never transformed.
   */
  @Local bgFade: number = 1;
  @Local chromeFade: number = 1;
  @Local roomTransitioning: boolean = false;
  @Local snapshotReturn: boolean = false;
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
  private mainDanmaku: DanmakuEngine | null = null;
  private backIssued: boolean = false;
  private rootHeld: boolean = false;
  private returnAnimating: boolean = false;
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
  @Local pipShown: boolean = false;
  private pipSupported: boolean = LivePip.supported();
  /** While going to the background with auto PiP armed, give the PiP window time to appear. */
  private pipGraceTimer: number = -1;
  private pipCloseTimer: number = -1;
  private bullets: RoomBulletDelivery = new RoomBulletDelivery(() => this.model.player.latencyMs);
  private pipDanmaku: PipDanmakuController = new PipDanmakuController((engine) => this.bullets.bindPip(engine));
  private pip: LivePip = new LivePip({
    play: () => {
      this.pausedByBackground = false;
      this.model.resume();
    },
    pause: () => this.pausePlayback(),
    onStarted: () => this.onPipStarted(),
    onStopped: (restoring: boolean) => this.onPipStopped(restoring),
    onActive: (active: boolean, restoring: boolean) => {
      if (this.disposed) return;
      this.clearPipCloseCheck();
      this.pipActive = active;
      if (!active) {
        this.pipShown = false;
        this.pipDanmaku.setVisible(false);
        this.onBulletPresentation();
      }
      if (active && this.pausedByBackground) {
        this.pausedByBackground = false;
        this.model.resume();
      }
      if (!active && !restoring && !this.env.foreground) {
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
    if (this.disposed) return;
    this.danmakuEnabled = this.settings.danmakuOn;
    this.sideChatEnabled = this.settings.sideChat;
    this.fillVideo = this.settings.videoFill;
    this.applyVolume(this.settings.volumeMode === 'app' ? this.settings.appVolume : 1);
    const s = this.settings;
    const style = `${s.danmakuSize}|${s.danmakuOpacity}|${s.danmakuSpeed}|${s.danmakuMax}|` +
      `${s.danmakuArea}|${s.danmakuStroke}|${s.danmakuKeepColor}`;
    if (style !== this.appliedDanmakuStyle) {
      this.appliedDanmakuStyle = style;
      this.danmakuStyleVersion++;
    }
    this.pipDanmaku.setEnabled(this.danmakuEnabled);
    this.pipDanmaku.setStyleVersion(this.danmakuStyleVersion);
    this.onBulletPresentation();
  }

  private applyVolume(volume: number): void {
    if (volume === this.appliedVolume) return;
    this.model.player.setVolume(volume);
    this.appliedVolume = volume;
  }

  @Monitor('env.foreground', 'presentationActive', 'fullscreen', 'panelOpen', 'drawerOpen', 'rootW', 'panelTab', 'sideChatEnabled')
  onChatPresentation(): void {
    if (this.disposed) return;
    const active = this.presentationActive && this.env.foreground &&
      (this.fullscreen ? this.sideChatEnabled : this.showPanel && this.panelTab === 0);
    this.model.setChatActive(active);
  }

  @Monitor('env.foreground', 'presentationActive', 'pipShown', 'danmakuEnabled')
  onBulletPresentation(): void {
    if (this.disposed) return;
    this.bullets.setPresentation(this.presentationActive && this.env.foreground,
      this.pipShown, this.danmakuEnabled);
  }

  @Monitor('model.switchSeq')
  onRoomSwitch(): void { this.bullets.clear(); }

  @Monitor('settings.danmakuOn', 'settings.danmakuSize', 'settings.danmakuOpacity', 'settings.danmakuSpeed',
    'settings.danmakuMax', 'settings.danmakuArea', 'settings.danmakuStroke', 'settings.danmakuKeepColor')
  onDanmakuSettings(): void { this.syncSettings(); }

  aboutToAppear(): void {
    if (this.disposed) return;
    this.env.subscribeForeground(this.foregroundListener);
    this.syncSettings();
    this.onChatPresentation();
    this.model.preview = this.route.preview;
  }

  onReady(ctx: NavDestinationContext): void {
    if (this.disposed) return;
    const p = ctx.pathInfo.param as LiveRouteParam;
    p.owner = this.playbackOwner;
    if (this.roomReady) return;
    this.roomReady = true;
    Log.i('page', `live onReady ${p.siteId} room=${p.roomId}`);
    this.sourceRoomKey = `${p.siteId}_${p.roomId}`;
    this.audioOwner = BackgroundAudio.attach(AppEnv.inst.context, {
      play: () => {
        this.pausedByBackground = false;
        this.model.resume();
      },
      pause: () => this.pausePlayback()
    });
    this.model.onBullet = (text: string, color: number) => this.bullets.push(text, color);
    this.model.open(p.siteId, p.roomId, p.preview);
    this.mount.start(this.getUIContext(), (stage: number) => {
      if (this.disposed || this.exiting) return;
      if (stage === 0) this.surfaceMounted = true;
      if (stage === 1) this.topMounted = true;
      if (stage === 2) this.bottomMounted = true;
      if (stage === 3) this.chromeMounted = true;
      if (stage === 5) this.glowMounted = true;
      if (stage === 4) {
        this.panelMounted = true;
        this.presentationActive = true;
        this.onChatPresentation();
        this.onBulletPresentation();
      }
    });
    if (Settings.inst.autoFullscreen) {
      this.setFullscreen(true, false);
    }
    this.armHide();
  }

  aboutToDisappear(): void {
    this.disposeRoom('component');
    if (!this.returnAnimating ||
      (Nav.stack.getAllPathName().length > 0 && !Nav.isLiveOwner(this.playbackOwner))) {
      this.releaseRootPresentation();
    }
  }

  private holdRootPresentation(): void {
    if (this.rootHeld) return;
    this.rootHeld = true;
    NavigationActivity.inst.holdRoot();
  }

  private releaseRootPresentation(): void {
    if (!this.rootHeld) return;
    this.rootHeld = false;
    // onHidden also covers SDK-cached destinations which do not immediately disappear.
    // Reconcile the list outside the framework's animation-finish/layout callback.
    setTimeout(() => PerfTrace.run('root.resume', () => NavigationActivity.inst.releaseRoot()), 0);
  }

  private disposeRoom(why: string): void {
    if (this.pipHandoff) return;
    if (this.disposed) {
      return;
    }
    Log.i('page', `live dispose by ${why}`);
    this.disposed = true;
    this.mount.cancel();
    this.clearPipStart();
    RetainedRoomPlayback.release(this.playbackOwner);
    this.presentationActive = false;
    this.restoreSheetKeyboard();
    this.env.unsubscribeForeground(this.foregroundListener);
    this.clearPipCloseCheck();
    this.clearBackCapture();
    PerfTrace.run('room.pip.dispose', () => this.pip.dispose());
    this.bullets.dispose();
    this.pipDanmaku.dispose();
    this.videoXc = null;
    this.mainDanmaku = null;
    this.clearPipGrace();
    PerfTrace.run('room.audio.detach', () => BackgroundAudio.detach(this.audioOwner));
    PerfTrace.run('room.model.dispose', () => this.model.dispose());
    PerfTrace.run('room.window.restore', () => {
      AppEnv.inst.setKeepScreenOn(false);
      AppEnv.inst.setBrightness(-1);
    });
    const restoreWindow = this.fullscreen || this.fullscreenTarget;
    this.fullscreen = false;
    this.fullscreenTarget = false;
    this.fullscreenSeq++;
    if (restoreWindow) {
      this.env.exitVideoFullscreen().catch(() => {});
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
      this.restoreMainDanmaku();
      this.onPlayState();
    }
  }

  private pausePlayback(): void {
    if (this.disposed) return;
    this.model.player.pause();
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
    const alive = !this.sleepExpired && state !== PlayState.Error && state !== PlayState.Idle;
    BackgroundAudio.update(alive && this.model.player.wantsPlayback,
      alive && this.model.player.wantsPlayback, leave !== 'pause', this.audioOwner);
    this.pip.setPlaying(active);
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

  get leaveBehavior(): LeaveBehavior {
    const leave = this.settings.leaveBehavior;
    return leave === 'pip' && !this.pipSupported ? 'pause' : leave;
  }

  private pauseForBackground(): void {
    if (this.disposed) return;
    if (this.env.foreground || this.leaveBehavior === 'audio' || this.pipActive) {
      return;
    }
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
    if (this.disposed || this.exiting || this.pipHandoff || this.pipStartRoom.length > 0) return;
    this.pipStartRoom = `${this.model.siteId}_${this.model.roomId}`;
    this.pipStartTimer = setTimeout(() => {
      this.pipStartTimer = -1;
      if (this.pipStartRoom.length === 0 || this.disposed) return;
      this.clearPipStart();
      this.pip.stop().catch(() => {});
      promptAction.showToast({ message: '画中画暂不可用' });
    }, 4000);
    this.pip.start().catch(() => {
      if (this.disposed || this.pipStartRoom.length === 0) return;
      this.clearPipStart();
      promptAction.showToast({ message: '画中画暂不可用' });
    });
  }

  private clearPipStart(): void {
    this.pipStartRoom = '';
    if (this.pipStartTimer >= 0) clearTimeout(this.pipStartTimer);
    this.pipStartTimer = -1;
  }

  private onPipStarted(): void {
    if (this.disposed) return;
    this.pipShown = true;
    this.pipDanmaku.setVisible(true);
    this.onBulletPresentation();
    if (this.pipStartRoom.length === 0) return;
    const room = this.pipStartRoom;
    this.clearPipStart();
    if (this.exiting || room !== `${this.model.siteId}_${this.model.roomId}` ||
      !Nav.isLiveOwner(this.playbackOwner)) return;
    this.pipHandoff = true;
    this.presentationActive = false;
    this.model.setChatActive(false);
    this.restoreSheetKeyboard();
    this.sheet = '';
    clearTimeout(this.hideTimer);
    clearTimeout(this.hudTimer);
    clearTimeout(this.panelHideTimer);
    this.env.setKeepScreenOn(false);
    this.env.setBrightness(-1);
    RetainedRoomPlayback.retain(this.playbackOwner, () => {
      this.pipHandoff = false;
      this.disposeRoom('retained PiP closed');
    });
    const leave = (): void => {
      if (!this.disposed && this.pipHandoff) Nav.popLiveOwner(this.playbackOwner);
    };
    const restoreWindow = this.fullscreen || this.fullscreenTarget;
    this.fullscreenTarget = false;
    this.fullscreenSeq++;
    if (restoreWindow) {
      this.fullscreen = false;
      this.env.exitVideoFullscreen().catch(() => {}).finally(() => leave());
    } else {
      leave();
    }
  }

  private onPipStopped(restoring: boolean): void {
    if (this.disposed || restoring) return;
    this.clearPipStart();
    this.bullets.clear();
    if (this.pipHandoff) {
      this.pipHandoff = false;
      this.disposeRoom('PiP window closed');
    }
  }

  private restoreMainDanmaku(): void {
    if (this.disposed || !this.presentationActive || !this.env.foreground || this.pipShown) return;
    this.bullets.bindMain(this.mainDanmaku);
    this.onBulletPresentation();
  }

  private onRoomShown(): void {
    if (this.disposed) return;
    this.pipHandoff = false;
    this.snapshotReturn = false;
    RetainedRoomPlayback.release(this.playbackOwner);
    this.presentationActive = this.panelMounted;
    this.restoreMainDanmaku();
    this.exiting = false;
    this.backIssued = false;
    this.syncSettings();
    this.onChatPresentation();
    this.onPlayState();
    this.armHide();
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
      return 380;
    }
    return this.narrow ? Math.min(330, Math.max(0, this.rootW - 24)) : 330;
  }

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
    this.panelHideTimer = setTimeout(() => {
      this.panelHideTimer = -1;
      if (!this.showPanel) {
        this.panelPresent = false;
      }
    }, 320);
  }

  get leftW(): number {
    return this.rootW - (this.showPanel && !this.narrow ? this.panelW + 16 : 0);
  }

  get topInset(): number {
    return this.env.statusBarHeight + 16;
  }

  get slotW(): number {
    const maxW = this.leftW - GAP * 2;
    const maxH = this.rootH - this.topInset - INFO_H - 20 - this.env.navBarHeight;
    return Math.max(0, Math.min(maxW, maxH * 16 / 9));
  }

  get slotH(): number {
    return this.slotW * 9 / 16;
  }

  get slotX(): number {
    return GAP + (this.leftW - GAP * 2 - this.slotW) / 2;
  }

  // ---------- behaviour ----------

  private get videoAspect(): number {
    const w = this.model.player?.videoWidth ?? 0;
    const h = this.model.player?.videoHeight ?? 0;
    return w > 0 && h > 0 ? w / h : 16 / 9;
  }

  private applyFullscreenUi(on: boolean, animated: boolean): void {
    if (!on) this.scToast = null;
    if (animated && !this.env.reduceMotion) {
      this.getUIContext().animateTo({ curve: Motion.hero }, () => { this.fullscreen = on; });
    } else {
      this.fullscreen = on;
    }
    this.showControls();
  }

  private setFullscreen(on: boolean, animated: boolean = true): void {
    if (this.disposed || this.pipHandoff || on === this.fullscreenTarget) return;
    this.fullscreenTarget = on;
    const seq = ++this.fullscreenSeq;
    if (on) {
      this.env.enterVideoFullscreen(this.videoAspect).then(() => {
        if (this.disposed || this.pipHandoff || seq !== this.fullscreenSeq || !this.fullscreenTarget) return;
        this.applyFullscreenUi(true, animated);
      }).catch((e: Error) => {
        if (this.disposed || this.pipHandoff || seq !== this.fullscreenSeq) return;
        this.fullscreenTarget = this.fullscreen;
        Log.w('page', `enter video fullscreen failed: ${e.message}`);
        promptAction.showToast({ message: '当前窗口不支持全屏切换' });
      });
    } else {
      this.applyFullscreenUi(false, animated);
      this.env.exitVideoFullscreen().catch((e: Error) => {
        Log.w('page', `exit video fullscreen failed: ${e.message}`);
      });
    }
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
    if (this.disposed) return;
    if (this.sheet !== '') {
      this.closeSheet();
      return;
    }
    this.controls = !this.controls;
    if (this.controls) {
      this.armHide();
    }
  }

  private restoreSheetKeyboard(): void {
    const context = this.sheetKeyboardContext;
    const previous = this.previousKeyboardMode;
    this.sheetKeyboardContext = null;
    this.previousKeyboardMode = null;
    if (context === null || previous === null) return;
    try {
      if (context.getKeyboardAvoidMode() === KeyboardAvoidMode.RESIZE) context.setKeyboardAvoidMode(previous);
    } catch (e) {
      Log.w('page', 'sheet keyboard context already detached');
    }
  }

  private openSheet(kind: SheetKind): void {
    if (this.disposed) return;
    if (kind === 'sleep' && this.sheetKeyboardContext === null) {
      const context = this.getUIContext();
      this.previousKeyboardMode = context.getKeyboardAvoidMode();
      this.sheetKeyboardContext = context;
      context.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } else if (kind !== 'sleep') {
      this.restoreSheetKeyboard();
    }
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
    if (this.disposed) return;
    this.restoreSheetKeyboard();
    this.getUIContext().animateTo({ curve: Motion.smooth }, () => {
      this.sheet = '';
    });
    this.armHide();
  }

  private changeVolume(v: number): void {
    if (this.disposed) return;
    if (this.settings.volumeMode === 'app') {
      if (v === this.settings.appVolume && v === this.appliedVolume) return;
      this.applyVolume(v);
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
    this.mediaWrite = this.mediaWrite.then(() => MediaVolume.write(level)).catch(() => false);
    this.mediaWrite.then((ok: boolean) => {
      if (!ok && !this.disposed && intent === this.mediaIntent &&
        roomKey === `${this.model.siteId}_${this.model.roomId}` && this.settings.volumeMode === 'media') {
        this.settings.volumeMode = 'app';
        this.applyVolume(this.settings.appVolume);
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
      Nav.popLiveOwner(this.playbackOwner);
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
      this.pipHandoff = false;
      this.finishSleep();
      this.disposeRoom('sleep deadline');
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
    this.followed = true;
    this.model.switchTo(f.siteId, f.roomId, f.toRoomItem());
  }

  private togglePanel(): void {
    const open = !this.showPanel;
    this.getUIContext().animateTo(this.env.reduceMotion ? { duration: 0 } : { curve: Motion.smooth }, () => {
      this.panelOpen = open;
      this.drawerOpen = this.narrow && open;
    });
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
    if (this.exiting || this.disposed || this.pipHandoff) return;
    this.exiting = true;
    this.returnAnimating = true;
    this.model.cancelSwitch();
    this.mount.cancel();
    this.presentationActive = false;
    this.onChatPresentation();
    this.onBulletPresentation();
    this.holdRootPresentation();
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
    if (xc === null || this.route.coverW <= 0 || this.env.reduceMotion || !this.model.player.firstFrame ||
      this.sourceRoomKey !== `${this.model.siteId}_${this.model.roomId}`) {
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
      if (this.backIssued || this.disposed) {
        pixel.release();
      } else {
        this.morphPixel = pixel;
      }
    } catch (e) {
      Log.w('page', 'last frame capture failed; leaving with the cover');
    }
  }

  private clearMorph(): void {
    this.morphOn = false;
    const pixel = this.morphPixel;
    this.morphPixel = null;
    if (pixel !== null) {
      RoomMount.afterPaint(this.getUIContext(), async (): Promise<void> => {
        try { await pixel.release(); } catch (e) { /* Already released during window teardown. */ }
      });
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
    Nav.stack.pop(true);
  }

  private playerRect(): number[] {
    return this.fullscreen ? [0, 0, this.rootW, this.rootH] :
      [this.slotX, this.topInset, this.slotW, this.slotH];
  }

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
    if (operation === NavigationOperation.POP && (this.pipHandoff || this.sleepPopIssued)) {
      this.returnAnimating = false;
      this.releaseRootPresentation();
      return undefined;
    }
    const reduce = this.env.reduceMotion;
    const fromCard = this.route.coverW > 0 && !reduce;
    if (isEnter && operation === NavigationOperation.PUSH) {
      this.roomTransitioning = true;
      this.bgFade = 0;
      this.chromeFade = 0;
      if (!fromCard) {
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
      this.returnAnimating = true;
      this.holdRootPresentation();
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
            this.clearMorph();
            this.returnAnimating = false;
            this.releaseRootPresentation();
          }
        }];
      }
      this.snapshotReturn = true;
      this.prepareMorph(this.playerRect());
      return [{
        duration: 280,
        curve: Curve.Friction,
        event: () => {
          this.setMorph(this.cardRect);
        },
        onTransitionEnd: () => {
          this.clearMorph();
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
          this.returnAnimating = false;
          this.releaseRootPresentation();
        }
      }];
    }
    return undefined;
  }

  get morphCover(): string {
    const preview = this.route.preview;
    return preview !== null && preview.cover.length > 0 ? preview.cover : this.model.cover;
  }

  private onBack(): boolean {
    if (this.sheet !== '') {
      this.closeSheet();
      return true;
    }
    if (this.fullscreen || this.fullscreenTarget) {
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
          if (this.fullscreen || this.fullscreenTarget) {
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
        LiveDot({ dim: 6 })
        Text(formatOnline(this.model.online))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(C.onMedia)
          .fontFeature('"tnum" on')
      }
      .padding({ left: 12, right: 14, top: 6, bottom: 6 })
      .borderRadius(Radius.pill)
      .backgroundColor('#4D000000')
      .backgroundBlurStyle(BlurStyle.Thin)
      if (this.fullscreen) {
        IconButton({ dim: 44,
          icon: this.followed ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
          glass: true, active: this.followed, activeTint: C.live, toggleState: true,
          label: this.followed ? '已关注' : '关注',
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
    .linearGradient({ angle: 180, colors: [['#80000000', 0], ['#00000000', 1]] })
  }

  @Builder
  pill(label: () => string, onTap: () => void) {
    Text(label())
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(C.onMedia)
      .height(40)
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
      .scrollBar(BarState.Off)
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
        glass: true, label: this.fullscreen ? '退出全屏' : '全屏', onTap: () => this.setFullscreen(!this.fullscreenTarget)
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 28, bottom: this.fullscreen ? Math.max(16, this.env.navBarHeight + 8) : 12 })
    .linearGradient({ angle: 0, colors: [['#80000000', 0], ['#00000000', 1]] })
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
        glass: true, active: this.danmakuEnabled, toggleState: true, label: this.danmakuEnabled ? '关闭弹幕' : '开启弹幕', onTap: () => {
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
    .width(Math.max(620, (this.fullscreen ? this.rootW : this.slotW) - 86))
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
        presentationActive: this.env.foreground && this.presentationActive && !this.pipShown,
        onDanmaku: (engine: DanmakuEngine | null) => {
          if (engine !== null) this.mainDanmaku = engine;
          this.bullets.bindMain(engine);
        },
        styleVersion: this.danmakuStyleVersion,
        cornerRadius: this.fullscreen ? 0 : Radius.xl,
        onSurface: (xc: XComponentController) => {
          if (this.disposed) return;
          this.videoXc = xc;
          this.pip.attach(AppEnv.inst.context, xc, Nav.id, this.pipDanmaku);
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
        if (this.topMounted) {
          this.topBar()
        }
        Blank()
        if (this.bottomMounted) {
          this.bottomBar()
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.controls ? 1 : 0)
      .translate({ y: this.controls ? 0 : 4 })
      .animation({ duration: 220, curve: Curve.EaseOut })
      .hitTestBehavior(this.controls ? HitTestMode.Default : HitTestMode.None)

      if (this.bottomMounted) {
        this.hudView()
      }
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
          .onAction(() => this.setFullscreen(!this.fullscreenTarget)),
        TapGesture({ count: 1 })
          .onAction(() => this.toggleControls()),
        LongPressGesture({ duration: 450 })
          .onAction(() => this.openSheet('follows')),
        PinchGesture()
          .onActionEnd((e: GestureEvent) => {
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

  /** Borderless Editorial Streamer Info Bar floating in pure negative space below the 16:9 video. */
  @Builder
  infoBar() {
    Row({ space: 16 }) {
      Avatar({ src: this.model.avatar, dim: 48, live: this.model.detail?.status ?? false })
      Column({ space: 6 }) {
        Text(this.model.title.length > 0 ? this.model.title : this.model.userName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(this.model.userName)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(C.text2)
          Text(`·  ${SiteStyle.label(this.model.siteId)}`)
            .fontSize(13)
            .fontColor(C.text3)
          if (this.model.area.length > 0) {
            Text(`·  ${this.model.area}`)
              .fontSize(13)
              .fontColor(C.text3)
          }
          if ((this.model.detail?.startTime ?? 0) > 0) {
            Text(`·  ${formatDuration(this.model.detail?.startTime ?? 0)}`)
              .fontSize(13)
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
        active: this.followed, activeTint: C.live, toggleState: true, label: this.followed ? '已关注' : '关注',
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

  @Local drawnPanelTabs: number[] = [0];
  @Local visitedPanelTabs: number[] = [0];
  private panelTabSeq: number = 0;

  private panelTabOffset(tab: number): number {
    if (this.env.reduceMotion || tab === this.panelTab) return 0;
    return tab < this.panelTab ? -24 : 24;
  }

  private selectPanelTab(next: number): void {
    if (next < 0 || next >= PANEL_TABS.length || next === this.panelTab) return;
    const seq = ++this.panelTabSeq;
    if (!this.visitedPanelTabs.includes(next)) {
      this.visitedPanelTabs = this.visitedPanelTabs.concat(next);
    }
    if (next === 1) {
      FollowStore.inst.refreshAll();
    }
    if (this.env.reduceMotion) {
      this.panelTab = next;
      this.drawnPanelTabs = [next];
      return;
    }
    if (!this.drawnPanelTabs.includes(next)) {
      this.drawnPanelTabs = this.drawnPanelTabs.concat(next);
    }
    this.getUIContext().animateTo({
      duration: 260,
      curve: Motion.snappy,
      onFinish: () => {
        if (!this.disposed && seq === this.panelTabSeq) {
          this.drawnPanelTabs = [this.panelTab];
        }
      }
    }, () => {
      this.panelTab = next;
    });
  }

  private onPanelSwipe(e: GestureEvent): void {
    const dx = e.offsetX;
    const dy = e.offsetY;
    if (Math.abs(dx) < 32 || Math.abs(dx) < Math.abs(dy) * 1.15) return;
    if (dx < 0 && this.panelTab < PANEL_TABS.length - 1) {
      this.selectPanelTab(this.panelTab + 1);
    } else if (dx > 0 && this.panelTab > 0) {
      this.selectPanelTab(this.panelTab - 1);
    }
  }

  /**
   * Borderless "Apple Music Live Lyrics" Right Panel:
   * Zero outer box or border in standard theater mode; clean editorial text tabs and top/bottom
   * gradient fade scrims over the live chat stream.
   */
  @Builder
  sidePanel() {
    Column() {
      Row({ space: 26 }) {
        ForEach(PANEL_TABS, (label: string, i: number) => {
          Column({ space: 5 }) {
            Text(label)
              .fontSize(this.panelTab === i ? 16 : 15)
              .fontWeight(this.panelTab === i ? FontWeight.Bolder : FontWeight.Medium)
              .fontColor(this.panelTab === i ? C.text1 : C.text3)
            Row()
              .width(this.panelTab === i ? 16 : 0)
              .height(2.5)
              .borderRadius(2)
              .backgroundColor(C.text1)
              .opacity(this.panelTab === i ? 1 : 0)
              .animation({ duration: 180, curve: Curve.EaseOut })
          }
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 6, bottom: 4 })
          .onClick(() => this.selectPanelTab(i))
        }, (label: string) => label)
        Blank()
        if (this.narrow) {
          IconButton({ dim: 44, icon: $r('sys.symbol.xmark'), label: '收起弹幕侧栏',
            onTap: () => this.togglePanel() })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 18, right: 18, top: 12, bottom: 8 })

      Stack() {
        Stack() {
          ChatList({ model: this.model, dark: this.env.isDark,
            active: this.env.foreground && this.presentationActive && this.showPanel && !this.fullscreen && this.panelTab === 0 })
        }
        .width('100%')
        .height('100%')
        .visibility(this.drawnPanelTabs.includes(0) ? Visibility.Visible : Visibility.None)
        .opacity(this.panelTab === 0 ? 1 : 0)
        .translate({ x: this.panelTabOffset(0) })
        .enabled(this.panelTab === 0)
        .hitTestBehavior(this.panelTab === 0 ? HitTestMode.Default : HitTestMode.None)

        if (this.visitedPanelTabs.includes(1)) {
          Stack() {
            LiveFollowList({
              currentKey: `${this.model.siteId}_${this.model.roomId}`,
              onPick: (f: FollowItem) => this.pickFollow(f)
            })
              .padding({ left: 8, right: 8 })
          }
          .width('100%')
          .height('100%')
          .visibility(this.drawnPanelTabs.includes(1) ? Visibility.Visible : Visibility.None)
          .opacity(this.panelTab === 1 ? 1 : 0)
          .translate({ x: this.panelTabOffset(1) })
          .enabled(this.panelTab === 1)
          .hitTestBehavior(this.panelTab === 1 ? HitTestMode.Default : HitTestMode.None)
        }

        if (this.visitedPanelTabs.includes(2)) {
          Stack() {
            RoomInfo({ model: this.model })
          }
          .width('100%')
          .height('100%')
          .visibility(this.drawnPanelTabs.includes(2) ? Visibility.Visible : Visibility.None)
          .opacity(this.panelTab === 2 ? 1 : 0)
          .translate({ x: this.panelTabOffset(2) })
          .enabled(this.panelTab === 2)
          .hitTestBehavior(this.panelTab === 2 ? HitTestMode.Default : HitTestMode.None)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .clip(true)
    }
    .width(this.panelW)
    .id('theater_chat_panel')
    .height(this.rootH - this.topInset - 16 - this.env.navBarHeight)
    .position({ x: this.rootW - this.panelW - 16, y: this.topInset })
    .borderRadius(Radius.xl)
    .backgroundColor(this.env.isDark ? C.glassTint : '#14000000')
    .backgroundBlurStyle(this.env.isDark ? BlurStyle.COMPONENT_THIN : BlurStyle.NONE)
    .clip(true)
    .renderGroup(this.roomTransitioning)
    .visibility(this.fullscreen || !this.panelPresent ? Visibility.None : Visibility.Visible)
    .opacity(this.showPanel && !this.fullscreen ? 1 : 0)
    .translate({ x: this.showPanel && !this.fullscreen ? 0 : 40 })
    .hitTestBehavior(this.showPanel && !this.fullscreen ? HitTestMode.Default : HitTestMode.None)
    .priorityGesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 16 })
        .onActionEnd((e: GestureEvent) => this.onPanelSwipe(e))
    )
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
        .height(Math.min(this.sheetOptionCount * this.sheetLayout.rowH, this.sheetLayout.bodyH))
    } else if (this.sheet === 'line') {
      OptionList({
        options: this.model.lines.map((u: string, i: number) => `线路 ${i + 1}${u.indexOf('.m3u8') >= 0 ? ' · HLS' : ''}`),
        selected: this.model.player.lineIndex,
        onPick: (i: number) => {
          this.closeSheet();
          this.model.selectLine(i);
        }
      })
        .height(Math.min(this.sheetOptionCount * this.sheetLayout.rowH, this.sheetLayout.bodyH))
    } else if (this.sheet === 'danmaku') {
      DanmakuSettingsPanel({ onChange: () => this.syncSettings() })
        .height(Math.min(560, this.sheetLayout.bodyH))
    } else if (this.sheet === 'sleep') {
      List({ space: 4 }) {
        ForEach([0, 15, 30, 60, 90], (minutes: number) => {
          ListItem() {
            OptionChoice({ label: minutes === 0 ? '关闭定时' : `${minutes} 分钟`,
              selected: this.sleepMinutes === minutes, onPick: () => this.setSleep(minutes) })
          }
        }, (minutes: number) => `${minutes}`)
        ListItem() {
          Row({ space: 10 }) {
            TextInput({ text: this.sleepInput, placeholder: '自定义分钟（1–720）' })
              .id('sleep_minutes')
              .type(InputType.Number).layoutWeight(1)
              .constraintSize({ minHeight: 44 })
              .backgroundColor('#26FFFFFF').fontColor(C.onMedia)
              .onChange((value: string) => { this.sleepInput = value; })
            Button('开始')
              .id('sleep_start')
              .fontColor(C.onAccent)
              .fontWeight(FontWeight.Bold)
              .constraintSize({ minHeight: 44 }).backgroundColor(C.accent)
              .onClick(() => {
                const minutes = Number(this.sleepInput);
                if (!/^\d{1,3}$/.test(this.sleepInput) || minutes < 1 || minutes > 720) {
                  promptAction.showToast({ message: '请输入 1–720 分钟' });
                  return;
                }
                this.setSleep(minutes);
              })
          }
          .padding({ left: 4, right: 4 })
          .margin({ top: 12 })
        }
        ListItem() {
          Text('时间到后结束播放并返回上一页')
            .fontSize(12).fontColor(C.onMedia2)
            .padding({ left: 8 }).margin({ top: 8 })
        }
      }
      .width('100%')
      .height(Math.min(this.sheetLayout.bodyH, 342 * Math.max(1, this.env.fontScale)))
      .padding({ left: 8, right: 8 })
      .contentEndOffset(4)
      .scrollBar(BarState.Off)
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

  @Computed
  get sheetLayout(): RoomSheetLayout {
    return layoutRoomSheet({ kind: this.sheet, width: this.rootW, height: this.rootH,
      topInset: this.topInset, navInset: this.env.navBarHeight, anchorX: this.sheetAnchorX, anchorY: this.sheetAnchorY,
      fontScale: this.env.fontScale, keyboardHeight: this.env.keyboardHeight, windowHeight: this.env.winHeight });
  }

  @Builder
  sheetLayer() {
    if (this.sheet !== '') {
      RoomSheet({ title: this.sheetTitle, layout: this.sheetLayout, reduceMotion: this.env.reduceMotion,
        onClose: () => this.closeSheet(), onRefresh: () => {
          if (!this.disposed) FollowStore.inst.refreshAll(true);
        } }) {
        this.sheetContent()
      }
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Stack() {
          if (this.glowMounted) {
            AmbientGlow({ src: this.model.cover, glowHeight: this.rootH, strength: this.fullscreen ? 0 : 0.72 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.fullscreen ? Color.Black : C.bg)
        .opacity(this.bgFade)

        Stack({ alignContent: Alignment.TopStart }) {
          if (this.chromeMounted) {
            this.infoBar()
          }

          Stack() {
            if (this.chromeMounted && !this.fullscreen) {
              Row()
                .width('100%')
                .height('100%')
                .backgroundColor(Color.Black)
                .borderRadius(Radius.xl)
                .shadow({ radius: 42, color: '#66000000', offsetY: 18 })
                .renderGroup(true)
                .hitTestBehavior(HitTestMode.None)
            }
            if (this.surfaceMounted) {
              this.videoStage()
            } else {
              Image(this.model.cover)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .syncLoad(false)
                .draggable(false)
                .borderRadius(this.fullscreen ? 0 : Radius.xl)
                .clip(true)
            }
          }
          .width(this.fullscreen ? this.rootW : this.slotW)
          .height(this.fullscreen ? this.rootH : this.slotH)
          .position({ x: this.fullscreen ? 0 : this.slotX, y: this.fullscreen ? 0 : this.topInset })
          .borderRadius(this.fullscreen ? 0 : Radius.xl)
          // The shadow is cached separately above; native video and frosted controls are not.
          // The return snapshot owns the moving picture. Keep the surface mounted, but do not
          // repaint its cover, controls and large shadow behind that opaque snapshot.
          .visibility(this.snapshotReturn ? Visibility.Hidden : Visibility.Visible)

          if (this.chromeMounted) {
            this.theaterActions()
            this.sheetLayer()
          }
          if (this.panelMounted) {
            this.sidePanel()
          }
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
    .backgroundColor(Color.Transparent)
    .onReady((ctx: NavDestinationContext) => this.onReady(ctx))
    .onShown(() => this.onRoomShown())
    .onHidden(() => {
      if ((!this.returnAnimating && !this.roomTransitioning) ||
        (Nav.stack.getAllPathName().length > 0 && !Nav.isLiveOwner(this.playbackOwner))) {
        this.releaseRootPresentation();
      }
    })
    .onBackPressed(() => this.onBack())
    .onWillDisappear(() => {
      if (!this.pipHandoff) this.holdRootPresentation();
      this.disposeRoom('navigation');
    })
    .customTransition((operation: NavigationOperation, isEnter: boolean) => this.roomTransition(operation, isEnter))
  }
}
