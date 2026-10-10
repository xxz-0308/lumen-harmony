import { common, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { accessibility } from '@kit.AccessibilityKit';
import { Log } from '../util/Log';

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
  private abilityForeground: boolean = true;
  private mainWindowVisible: boolean = true;

  subscribeForeground(listener: () => void): void {
    this.foregroundListeners.add(listener);
  }

  unsubscribeForeground(listener: () => void): void {
    this.foregroundListeners.delete(listener);
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
    env.win = win;
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
    AppEnv.inst.stopWatchingMotion();
    AppEnv.inst.win = null;
    AppEnv.inst.keyboardHeight = 0;
    AppEnv.setWindowVisible(false);
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
    this.isDark = this.themeMode === ThemeMode.Dark ? true :
      this.themeMode === ThemeMode.Light ? false : this.systemDark;
    this.applySystemBarStyle();
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

  /** Hides status/navigation bars for the fullscreen player. */
  setImmersive(on: boolean): void {
    this.immersive = on;
    const w = this.win;
    if (w === null) {
      return;
    }
    w.setSpecificSystemBarEnabled('status', !on).catch(() => {
    });
    w.setSpecificSystemBarEnabled('navigationIndicator', !on).catch(() => {
    });
    this.applySystemBarStyle();
  }

  /**
   * Small windows open portrait; a fullscreen video needs landscape. Restores auto rotation
   * when leaving fullscreen so the rest of the app keeps following the device.
   */
  setLandscape(on: boolean): void {
    const w = this.win;
    if (w === null) {
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
