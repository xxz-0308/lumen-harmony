import { curves } from '@kit.ArkUI';
import { SiteId } from '../core/model/Models';
import { Settings } from '../app/Settings';
import { AppEnv } from '../app/AppEnv';

/** Neutral colors come from resources (base/dark qualifiers); these are the typed handles. */
export class C {
  static readonly bg: Resource = $r('app.color.bg');
  static readonly bgElevated: Resource = $r('app.color.bg_elevated');
  static readonly surface: Resource = $r('app.color.surface');
  static readonly surface2: Resource = $r('app.color.surface_2');
  static readonly surface3: Resource = $r('app.color.surface_3');
  static readonly stroke: Resource = $r('app.color.stroke');
  static readonly strokeStrong: Resource = $r('app.color.stroke_strong');
  static readonly text1: Resource = $r('app.color.text_primary');
  static readonly text2: Resource = $r('app.color.text_secondary');
  static readonly text3: Resource = $r('app.color.text_tertiary');
  static readonly glassTint: Resource = $r('app.color.glass_tint');
  static readonly glassStroke: Resource = $r('app.color.glass_stroke');
  /** The lit selection pill inside a glass segmented control. */
  static readonly glassPill: Resource = $r('app.color.glass_pill');
  /** Translucent tint keeps the dock's backdrop visible on the API 24 glass path. */
  static get navSurface(): string { return AppEnv.inst.isDark ? '#661A1A22' : '#66FFFFFF'; }
  static get navStroke(): string { return AppEnv.inst.isDark ? '#24FFFFFF' : '#66FFFFFF'; }
  static get navHighlight(): string { return AppEnv.inst.isDark ? '#33FFFFFF' : '#99FFFFFF'; }
  static get navShadow(): string { return AppEnv.inst.isDark ? '#26000000' : '#14000000'; }
  static readonly skeleton: Resource = $r('app.color.skeleton');
  static readonly skeletonHi: Resource = $r('app.color.skeleton_hi');
  static get accent(): Resource | string {
    const mode = Settings.inst.accentPalette;
    if (mode === 'ocean') return AppEnv.inst.isDark ? '#78B9FF' : '#327DCE';
    if (mode === 'mint') return AppEnv.inst.isDark ? '#73D9B6' : '#147D67';
    if (mode === 'orchid') return AppEnv.inst.isDark ? '#CF9CFF' : '#8E4FC2';
    return $r('app.color.accent');
  }
  static get accentSoft(): Resource | string {
    const mode = Settings.inst.accentPalette;
    if (mode === 'ocean') return AppEnv.inst.isDark ? '#253C59' : '#E4F1FF';
    if (mode === 'mint') return AppEnv.inst.isDark ? '#1E473D' : '#D9F7EC';
    if (mode === 'orchid') return AppEnv.inst.isDark ? '#453358' : '#F3E4FF';
    return $r('app.color.accent_soft');
  }
  static get accentHighlight(): Resource | string {
    const mode = Settings.inst.accentPalette;
    if (mode === 'ocean') return '#5AA9F5';
    if (mode === 'mint') return '#36AC8A';
    if (mode === 'orchid') return '#B579E0';
    return '#FF8A4C';
  }
  static get accentGlow(): string {
    const mode = Settings.inst.accentPalette;
    if (mode === 'ocean') return '#66327DCE';
    if (mode === 'mint') return '#66147D67';
    if (mode === 'orchid') return '#668E4FC2';
    return '#66FF6B45';
  }
  static readonly live: Resource = $r('app.color.live');
  static readonly scrim: Resource = $r('app.color.scrim');
  static readonly heroFade: Resource = $r('app.color.hero_fade');
  /** Always-light text over video/cover imagery. */
  static readonly onMedia: string = '#FFFFFF';
  static readonly onMedia2: string = '#CCFFFFFF';
  static readonly onMedia3: string = '#8CFFFFFF';
}

export class Space {
  static readonly xxs: number = 4;
  static readonly xs: number = 8;
  static readonly sm: number = 12;
  static readonly md: number = 16;
  static readonly lg: number = 20;
  static readonly xl: number = 24;
  static readonly xxl: number = 32;
  static readonly page: number = 28;
}

export class Radius {
  static readonly xs: number = 6;
  static readonly sm: number = 10;
  static readonly md: number = 14;
  static readonly lg: number = 18;
  static readonly xl: number = 24;
  static readonly pill: number = 999;
}

export class Font {
  static readonly display: number = 34;
  static readonly title1: number = 26;
  static readonly title2: number = 20;
  static readonly headline: number = 17;
  static readonly body: number = 15;
  static readonly callout: number = 14;
  static readonly caption: number = 12;
  static readonly micro: number = 10;
}

/**
 * Motion vocabulary. Everything uses springs so interrupted animations stay continuous.
 * Durations are only used for opacity-only fades.
 */
export class Motion {
  /** Quick UI feedback: pills, toggles, press states. */
  static readonly snappy: ICurve = curves.springMotion(0.3, 0.86);
  /** Default for layout / position changes. */
  static readonly smooth: ICurve = curves.springMotion(0.42, 0.9);
  /** Slightly playful, for small elements appearing. */
  static readonly lively: ICurve = curves.springMotion(0.38, 0.74);
  /** Hero/shared-element transitions. */
  static readonly hero: ICurve = curves.interpolatingSpring(0, 1, 280, 30);
  static readonly fadeMs: number = 220;
  static readonly slowFadeMs: number = 600;
}

export class SiteStyle {
  static color(id: SiteId | string): string {
    if (id === 'douyu') {
      return '#FF6A2B';
    }
    if (id === 'bilibili') {
      return '#FB7299';
    }
    return '#FFA200';
  }

  static label(id: SiteId | string): string {
    if (id === 'douyu') {
      return '斗鱼';
    }
    if (id === 'bilibili') {
      return 'B站';
    }
    return '虎牙';
  }
}

/** Layout breakpoints in vp, tuned for the MatePad Pro 12.2 (≈1240×820vp landscape). */
export class Layout {
  static readonly touchTarget: number = 48;
  static readonly bottomNavHeight: number = 56;
  static readonly bottomNavGap: number = 8;
  static readonly bottomNavMaxWidth: number = 380;

  /** End space inside scrollable content, not a left-rail placeholder. */
  static get pageBottom(): number {
    return Space.xl + AppEnv.inst.navBarHeight;
  }

  static get bottomNavInset(): number {
    return Layout.bottomNavHeight + Layout.bottomNavGap * 2 + Layout.pageBottom;
  }

  static columns(contentWidth: number, minCard: number, gap: number): number {
    return Math.max(1, Math.floor((contentWidth + gap) / (minCard + gap)));
  }

  static isCompact(width: number): boolean {
    return width < 600;
  }
}

export function formatOnline(n: number): string {
  if (n >= 100000000) {
    return `${(n / 100000000).toFixed(1)}亿`;
  }
  if (n >= 10000) {
    const w = n / 10000;
    return `${w >= 100 ? Math.round(w) : w.toFixed(1)}万`;
  }
  return `${Math.max(0, Math.round(n))}`;
}

export function formatDuration(sinceUnixSec: number): string {
  if (sinceUnixSec <= 0) {
    return '';
  }
  const secs = Math.max(0, Math.floor(Date.now() / 1000) - sinceUnixSec);
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  return h > 0 ? `已播 ${h} 小时 ${m} 分` : `已播 ${m} 分钟`;
}

export function relativeTime(ms: number): string {
  const diff = Date.now() - ms;
  const min = Math.floor(diff / 60000);
  if (min < 1) {
    return '刚刚';
  }
  if (min < 60) {
    return `${min} 分钟前`;
  }
  const h = Math.floor(min / 60);
  if (h < 24) {
    return `${h} 小时前`;
  }
  const d = Math.floor(h / 24);
  if (d < 30) {
    return `${d} 天前`;
  }
  const date = new Date(ms);
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

/** Converts 0xRRGGBB plus alpha 0..1 into an ArkUI #AARRGGBB string. */
export function argb(rgb: number, alpha: number): string {
  const a = Math.round(Math.max(0, Math.min(1, alpha)) * 255);
  const hex = (v: number): string => (v < 16 ? '0' : '') + v.toString(16);
  return `#${hex(a)}${hex((rgb >> 16) & 0xff)}${hex((rgb >> 8) & 0xff)}${hex(rgb & 0xff)}`.toUpperCase();
}
