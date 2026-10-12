import { common, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { accessibility } from '@kit.AccessibilityKit';
import { Log } from '../util/Log';
import {
  copyWindowRect,
  floatingVideoSize,
  sameWindowRect,
  VideoFullscreenMode,
  VideoFullscreenSession
} from './WindowVideoGeometry';

export { VideoFullscreenMode };

export enum ThemeMode {
  System = 0,
  Light = 1,
  Dark = 2
}

/**
 * Process-wide environment: window handle, insets, resolved color mode and screen helpers.
 * Observed so layouts react to window resizes (split screen / floating window).
 */
@ObservedV2
export class AppEnv {
  static readonly inst: AppEnv = new AppEnv();

  context: common.UIAbilityContext | null = null;
  win: window.Window | null = null;

  @Trace isDark: boolean = true;
  @Trace statusBarHeight: number = 0;
  @Trace navBarHeight: number = 0;
  @Trace keyboardHeight: number = 0;
  @Trace fontScale: number = 1;
  @Trace winWidth: number = 1200;
  @Trace winHeight: number = 800;
  @Trace foreground: boolean = true;
  @Trace immersive: boolean = false;
  @Trace reduceMotion: boolean = false;
  @Trace isFloatingWindow: boolean = false;
  @Trace videoFullscreenMode: VideoFullscreenMode = VideoFullscreenMode.None;

  private windowStatus: window.WindowStatusType = window.WindowStatusType.UNDEFINED;
  private fullscreenSession: VideoFullscreenSession | null = null;
  private fullscreenIntent: number = 0;
  private windowEpoch: number = 0;
  private fullscreenQueue: Promise<void> = Promise.resolve();
  private statusListening: boolean = false;
  private rectListening: boolean = false;
  private onWindowStatusChanged: (status: window.WindowStatusType) => void =
    (status: window.WindowStatusType): void => {
      if (status !== this.windowStatus && this.fullscreenSession !== null) {
        this.fullscreenSession.geometryChanged = true;
        this.videoFullscreenMode = VideoFullscreenMode.None;
      }
      this.windowStatus = status;
      this.isFloatingWindow = status === window.WindowStatusType.FLOATING;
    };
  private onWindowRectChanged: (change: window.RectChangeOptions) => void =
    (change: window.RectChangeOptions): void => {
      const session = this.fullscreenSession;
      if (session === null || !session.floating) return;
      const reason = change.reason;
      if (reason === window.RectChangeReason.MOVE || reason === window.RectChangeReason.DRAG ||
        reason === window.RectChangeReason.DRAG_START || reason === window.RectChangeReason.DRAG_END ||
        (!session.resizing && session.appliedRect !== null &&
        !sameWindowRect(change.rect, session.appliedRect))) {
        session.geometryChanged = true;
      }
    };

  private onKeyboardChanged: (height: number) => void = (height: number): void => {
    this.keyboardHeight = this.px2vp(Math.max(0, height));
  };
  private motionListening: boolean = false;
  private onMotionChanged: (enabled: boolean) => void = (enabled: boolean): void => {
    this.reduceMotion = enabled;
  };

  private themeMode: ThemeMode = ThemeMode.System;
  private systemDark: boolean = true;
  private foregroundListeners: Set<() => void> = new Set<() => void>();
  private darkListeners: Set<() => void> = new Set<() => void>();
  private abilityForeground: boolean = true;
  private mainWindowVisible: boolean = true;

  subscribeForeground(listener: () => void): void {
    this.foregroundListeners.add(listener);
  }

  unsubscribeForeground(listener: () => void): void {
    this.foregroundListeners.delete(listener);
  }

  subscribeDark(listener: () => void): void {
    this.darkListeners.add(listener);
  }

  unsubscribeDark(listener: () => void): void {
    this.darkListeners.delete(listener);
  }

  static init(ctx: common.UIAbilityContext): void {
    AppEnv.inst.context = ctx;
    AppEnv.inst.fontScale = ctx.config.fontSizeScale ?? 1;
    AppEnv.inst.systemDark =
      ctx.config.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    AppEnv.inst.resolveDark();
  }

  static attachWindow(win: window.Window): void {
    const env = AppEnv.inst;
    if (env.win !== null) AppEnv.detachWindow();
    env.win = win;
    env.watchVideoWindow(win);
    env.watchMotion();
    AppEnv.setWindowVisible(true);
    try {
      win.setWindowLayoutFullScreen(true);
      env.updateInsets();
      win.on('avoidAreaChange', () => env.updateInsets());
      win.on('windowSizeChange', (size: window.Size) => env.updateSize(size.width, size.height));
      win.on('keyboardHeightChange', env.onKeyboardChanged);
      win.on('windowVisibilityChange', (visible: boolean) => {
        Log.i('env', `main window visible=${visible}`);
        AppEnv.setWindowVisible(visible);
      });
      const props = win.getWindowProperties();
      env.updateSize(props.windowRect.width, props.windowRect.height);
      env.applySystemBarStyle();
    } catch (e) {
      Log.e('env', `attachWindow ${JSON.stringify(e)}`);
    }
  }

  static detachWindow(): void {
    const w = AppEnv.inst.win;
    if (w !== null) {
      try {
        w.off('avoidAreaChange');
        w.off('windowSizeChange');
        w.off('windowVisibilityChange');
        w.off('keyboardHeightChange', AppEnv.inst.onKeyboardChanged);
      } catch (e) {
        // window already gone
      }
    }
    AppEnv.inst.stopWatchingVideoWindow(w);
    AppEnv.inst.stopWatchingMotion();
    AppEnv.inst.win = null;
    AppEnv.inst.keyboardHeight = 0;
    AppEnv.setWindowVisible(false);
  }

  private watchVideoWindow(win: window.Window): void {
    try {
      this.onWindowStatusChanged(win.getWindowStatus());
      win.on('windowStatusChange', this.onWindowStatusChanged);
      this.statusListening = true;
    } catch (e) {
      Log.w('env', 'window status observation unavailable');
    }
    try {
      win.on('windowRectChange', this.onWindowRectChanged);
      this.rectListening = true;
    } catch (e) {
      Log.w('env', 'window rectangle observation unavailable');
    }
  }

  private stopWatchingVideoWindow(win: window.Window | null): void {
    if (win !== null) {
      try {
        if (this.statusListening) win.off('windowStatusChange', this.onWindowStatusChanged);
      } catch (e) {
        // window already gone
      }
      try {
        if (this.rectListening) win.off('windowRectChange', this.onWindowRectChanged);
      } catch (e) {
        // window already gone
      }
    }
    this.statusListening = false;
    this.rectListening = false;
    this.windowEpoch++;
    this.fullscreenIntent++;
    this.fullscreenSession = null;
    this.videoFullscreenMode = VideoFullscreenMode.None;
    this.windowStatus = window.WindowStatusType.UNDEFINED;
    this.isFloatingWindow = false;
  }

  private watchMotion(): void {
    // These APIs are available since API 23, below our API 24 baseline.
    try {
      this.reduceMotion = accessibility.isAnimationReduceEnabledSync();
      if (!this.motionListening) {
        accessibility.onAnimationReduceStateChange(this.onMotionChanged);
        this.motionListening = true;
      }
    } catch (e) {
      Log.w('env', 'animation accessibility setting unavailable');
    }
  }

  private stopWatchingMotion(): void {
    if (!this.motionListening) {
      return;
    }
    try {
      accessibility.offAnimationReduceStateChange(this.onMotionChanged);
    } catch (e) {
      Log.w('env', 'animation accessibility listener cleanup failed');
    }
    this.motionListening = false;
  }

  static setWindowVisible(visible: boolean): void {
    const env = AppEnv.inst;
    env.mainWindowVisible = visible;
    AppEnv.updateForeground();
  }

  static setAbilityForeground(active: boolean): void {
    const env = AppEnv.inst;
    env.abilityForeground = active;
    AppEnv.updateForeground();
  }

  private static updateForeground(): void {
    const env = AppEnv.inst;
    const foreground = env.abilityForeground && env.mainWindowVisible;
    if (env.foreground === foreground) {
      return;
    }
    env.foreground = foreground;
    env.foregroundListeners.forEach((listener: () => void) => listener());
  }

  static syncSystemColorMode(config: Configuration): void {
    if (config.fontSizeScale !== undefined) AppEnv.inst.fontScale = config.fontSizeScale;
    // The ability callback's newConfig is authoritative; ctx.config may still hold the old mode.
    if (AppEnv.inst.themeMode === ThemeMode.System) {
      AppEnv.inst.systemDark = config.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    AppEnv.inst.resolveDark();
  }

  setThemeMode(mode: ThemeMode): void {
    Log.i('env', `apply theme mode=${mode}`);
    this.themeMode = mode;
    const ctx = this.context;
    if (ctx !== null) {
      const cm = mode === ThemeMode.Dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
        mode === ThemeMode.Light ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      ctx.getApplicationContext().setColorMode(cm);
    }
    this.resolveDark();
  }

  private resolveDark(): void {
    const prev = this.isDark;
    this.isDark = this.themeMode === ThemeMode.Dark ? true :
      this.themeMode === ThemeMode.Light ? false : this.systemDark;
    this.applySystemBarStyle();
    if (prev !== this.isDark) {
      this.darkListeners.forEach((listener: () => void) => listener());
    }
  }

  private px2vp(px: number): number {
    try {
      const d = display.getDefaultDisplaySync();
      return px / d.densityPixels;
    } catch (e) {
      return px / 2;
    }
  }

  private updateInsets(): void {
    const w = this.win;
    if (w === null) {
      return;
    }
    const sys = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const nav = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.statusBarHeight = this.px2vp(sys.topRect.height);
    this.navBarHeight = this.px2vp(nav.bottomRect.height);
  }

  private updateSize(wPx: number, hPx: number): void {
    this.winWidth = this.px2vp(wPx);
    this.winHeight = this.px2vp(hPx);
  }

  applySystemBarStyle(): void {
    const w = this.win;
    if (w === null) {
      return;
    }
    const light = !this.isDark && !this.immersive;
    w.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: light ? '#E6000000' : '#E6FFFFFF',
      navigationBarContentColor: light ? '#E6000000' : '#E6FFFFFF'
    }).catch((e: BusinessError) => Log.w('env', `bar style ${e.code}`));
  }

  /**
   * Floating main windows stay FLOATING: resize the same native window, without screen rotation.
   * Rejects unsupported/no-op resize and superseded requests. Commit the page's video-only UI
   * only after this resolves; layout must use its measured root, not the requested native size.
   */
  enterVideoFullscreen(aspect: number): Promise<void> {
    return this.queueVideoFullscreen(true, aspect);
  }

  /** Restore only geometry still owned by this session; never undo a subsequent user move/resize. */
  exitVideoFullscreen(): Promise<void> {
    return this.queueVideoFullscreen(false, 16 / 9);
  }

  private queueVideoFullscreen(enter: boolean, aspect: number): Promise<void> {
    const intent = ++this.fullscreenIntent;
    const epoch = this.windowEpoch;
    const win = this.win;
    const task = this.fullscreenQueue.then(async (): Promise<void> => {
      if (intent !== this.fullscreenIntent) throw new Error('Video fullscreen request superseded');
      if (win === null || this.win !== win || epoch !== this.windowEpoch) {
        throw new Error('Video fullscreen window detached or replaced');
      }
      if (enter) {
        await this.enterFullscreenWindow(win, aspect, intent);
      } else {
        const session = this.fullscreenSession;
        if (session !== null) await this.restoreFullscreenWindow(session);
      }
      if (this.win !== win || epoch !== this.windowEpoch) {
        throw new Error('Video fullscreen window detached or replaced');
      }
      if (intent !== this.fullscreenIntent) throw new Error('Video fullscreen request superseded');
    });
    // A rejection is returned to the caller, but must not poison the next queued intent.
    this.fullscreenQueue = task.catch(() => {});
    return task;
  }

  private ownsFullscreenWindow(session: VideoFullscreenSession): boolean {
    if (this.win !== session.win || this.fullscreenSession !== session) return false;
    try {
      const props = session.win.getWindowProperties();
      return props.id === session.id && props.displayId === session.displayId;
    } catch (e) {
      return false;
    }
  }

  private readWindowStatus(win: window.Window): window.WindowStatusType {
    const status = win.getWindowStatus();
    this.onWindowStatusChanged(status);
    return status;
  }

  private async enterFullscreenWindow(win: window.Window, aspect: number, intent: number): Promise<void> {
    if (!Number.isFinite(aspect) || aspect <= 0) throw new Error('Invalid video aspect ratio');
    const floating = this.readWindowStatus(win) === window.WindowStatusType.FLOATING;
    let session = this.fullscreenSession;
    if (session === null) {
      session = new VideoFullscreenSession(win, floating, this.immersive);
      this.fullscreenSession = session;
    }
    if (!this.ownsFullscreenWindow(session) || session.floating !== floating || session.geometryChanged) {
      throw new Error('Video fullscreen window changed; exit before re-entering');
    }
    try {
      if (floating) {
        if (!this.statusListening || !this.rectListening) {
          throw new Error('Cannot safely observe floating window geometry');
        }
        if (session.appliedRect === null) {
          const props = win.getWindowProperties();
          const screen = props.displayId === undefined ? display.getDefaultDisplaySync() :
            display.getDisplayByIdSync(props.displayId);
          const size = floatingVideoSize(props.windowRect, win.getWindowLimits(), screen, aspect);
          session.resizing = true;
          try {
            await win.resizeAsync(size.width, size.height);
          } finally {
            session.resizing = false;
          }
          if (!this.ownsFullscreenWindow(session)) throw new Error('Video fullscreen window replaced');
          const actual = win.getWindowProperties().windowRect;
          session.appliedRect = copyWindowRect(actual);
          if (actual.width <= actual.height || Math.abs(actual.width - size.width) > 2 ||
            Math.abs(actual.height - size.height) > 2) {
            throw new Error('Native floating window resize did not apply the requested landscape size');
          }
        }
        if (this.readWindowStatus(win) !== window.WindowStatusType.FLOATING || session.geometryChanged ||
          win.getPreferredOrientation() !== session.priorOrientation ||
          !sameWindowRect(win.getWindowProperties().windowRect, session.appliedRect!)) {
          throw new Error('Floating fullscreen window changed during resize');
        }
      } else {
        await win.setPreferredOrientation(window.Orientation.LANDSCAPE);
        if (!this.ownsFullscreenWindow(session)) throw new Error('Video fullscreen window replaced');
        if (this.readWindowStatus(win) === window.WindowStatusType.FLOATING || session.geometryChanged) {
          throw new Error('Video fullscreen window mode changed during orientation request');
        }
      }
      if (intent !== this.fullscreenIntent) throw new Error('Video fullscreen request superseded');
      if (!floating) this.setImmersive(true);
      this.videoFullscreenMode = floating ? VideoFullscreenMode.Floating : VideoFullscreenMode.Immersive;
    } catch (e) {
      // A newer intent handles restoration itself after the in-flight native operation settles.
      if (intent === this.fullscreenIntent && this.ownsFullscreenWindow(session)) {
        try {
          await this.restoreFullscreenWindow(session);
        } catch (restoreError) {
          Log.e('env', `fullscreen failure ${JSON.stringify(e)}, restore ${JSON.stringify(restoreError)}`);
          throw new Error('Video fullscreen failed and the original window could not be restored');
        }
      }
      throw new Error(`${e}`);
    }
  }

  private async restoreFullscreenWindow(session: VideoFullscreenSession): Promise<void> {
    try {
      if (!this.ownsFullscreenWindow(session)) throw new Error('Video fullscreen window replaced');
      const win = session.win;
      const floating = this.readWindowStatus(win) === window.WindowStatusType.FLOATING;
      if (session.floating) {
        const applied = session.appliedRect;
        if (!floating || session.geometryChanged || applied === null ||
          win.getPreferredOrientation() !== session.priorOrientation ||
          !sameWindowRect(win.getWindowProperties().windowRect, applied)) {
          Log.i('env', 'skip floating restore: geometry/mode no longer owned');
          return;
        }
        if (!sameWindowRect(applied, session.originalRect)) {
          session.resizing = true;
          try {
            await win.resizeAsync(session.originalRect.width, session.originalRect.height);
          } finally {
            session.resizing = false;
          }
          if (!this.ownsFullscreenWindow(session) ||
            this.readWindowStatus(win) !== window.WindowStatusType.FLOATING ||
            !sameWindowRect(win.getWindowProperties().windowRect, session.originalRect)) {
            throw new Error('Native floating window restore did not apply the original rectangle');
          }
        }
      } else if (!floating && !session.geometryChanged) {
        if (win.getPreferredOrientation() === window.Orientation.LANDSCAPE) {
          await win.setPreferredOrientation(session.priorOrientation);
        }
        if (!this.ownsFullscreenWindow(session)) throw new Error('Video fullscreen window replaced');
        if (this.readWindowStatus(win) !== window.WindowStatusType.FLOATING && !session.geometryChanged) {
          this.setImmersive(session.priorImmersive);
        }
      }
    } finally {
      if (this.fullscreenSession === session) {
        this.fullscreenSession = null;
        this.videoFullscreenMode = VideoFullscreenMode.None;
      }
    }
  }

  /** Hides status/navigation bars for the fullscreen player. */
  setImmersive(on: boolean): void {
    const w = this.win;
    if (w !== null) {
      try {
        if (this.readWindowStatus(w) === window.WindowStatusType.FLOATING) return;
      } catch (e) {
        Log.w('env', 'cannot apply immersive policy without window status');
        return;
      }
    }
    this.immersive = on;
    if (w === null) {
      return;
    }
    w.setSpecificSystemBarEnabled('status', !on).catch(() => {
    });
    w.setSpecificSystemBarEnabled('navigationIndicator', !on).catch(() => {
    });
    this.applySystemBarStyle();
  }

  /** Legacy orientation helper. Floating video must use enterVideoFullscreen instead. */
  setLandscape(on: boolean): void {
    const w = this.win;
    if (w === null) {
      return;
    }
    try {
      if (this.readWindowStatus(w) === window.WindowStatusType.FLOATING) return;
    } catch (e) {
      Log.w('env', 'cannot apply orientation policy without window status');
      return;
    }
    w.setPreferredOrientation(on ? window.Orientation.LANDSCAPE : window.Orientation.AUTO_ROTATION)
      .catch((e: BusinessError) => Log.w('env', `orientation ${e.code}`));
  }

  setKeepScreenOn(on: boolean): void {
    this.win?.setWindowKeepScreenOn(on).catch(() => {
    });
  }

  /** 0..1 sets window brightness; negative restores the system value. */
  setBrightness(v: number): void {
    this.win?.setWindowBrightness(v < 0 ? -1 : Math.max(0.01, Math.min(1, v))).catch(() => {
    });
  }

  getBrightness(): number {
    const w = this.win;
    if (w === null) {
      return 0.5;
    }
    const b = w.getWindowProperties().brightness;
    return b < 0 ? 0.5 : b;
  }
}
