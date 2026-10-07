import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SiteId } from '../core/model/Models';
import { AppEnv, ThemeMode } from './AppEnv';
import { Sites } from '../core/sites/Sites';
import { Log } from '../util/Log';

export type StartPage = 'home' | 'follow' | 'category' | 'mine' | 'history';
export type LeaveBehavior = 'pip' | 'pause' | 'audio';
export type DanmakuStroke = 'stroke' | 'shadow' | 'none';
export type AccentPalette = 'ember' | 'ocean' | 'mint' | 'orchid';
export type VolumeMode = 'media' | 'app';
/** 'ijk' = FFmpeg ijkplayer (default, keeps a large reserve); 'avplayer' = the system player. */
export type PlayerEngineChoice = 'ijk' | 'avplayer';

class SettingsData {
  themeMode: number = ThemeMode.System;
  accentPalette: string = 'ember';
  startPage: string = 'home';
  homeSite: string = 'huya';
  categorySite: string = 'huya';
  autoFullscreen: boolean = false;
  capAt1080: boolean = false;
  autoSwitchLine: boolean = true;
  leaveBehavior: string = 'pip';
  playerEngine: string = 'ijk';
  videoFill: boolean = false;
  volumeMode: string = 'media';
  appVolume: number = 1;
  danmakuOn: boolean = true;
  danmakuSize: number = 20;
  danmakuOpacity: number = 0.85;
  danmakuArea: number = 0.5;
  danmakuSpeed: number = 1.0;
  danmakuStroke: string = 'stroke';
  danmakuKeepColor: boolean = true;
  danmakuMax: number = 60;
  theaterPanelOpen: boolean = true;
  sideChat: boolean = false;
  showSuperChat: boolean = true;
  blockWords: string[] = [];
  searchHistory: string[] = [];
  favCategories: string[] = [];
  heroAutoPlay: boolean = false;
  biliUid: number = 0;
  biliName: string = '';
  biliExpired: boolean = false;
}

class LegacySettingsData extends SettingsData {
  biliCookie?: string;
}

/** User preferences. Call `scheduleSave()` after every mutation; @Monitor does not fire here. */
@ObservedV2
export class Settings {
  static readonly inst: Settings = new Settings();
  private store: preferences.Preferences | null = null;
  private context: common.Context | null = null;
  private unavailableBase: SettingsData | null = null;
  @Trace storageError: string = '';
  private storageListeners: Set<() => void> = new Set<() => void>();
  private accountListeners: Set<() => void> = new Set<() => void>();
  private loading: boolean = false;

  subscribeStorage(listener: () => void): void {
    this.storageListeners.add(listener);
  }

  unsubscribeStorage(listener: () => void): void {
    this.storageListeners.delete(listener);
  }

  subscribeAccount(listener: () => void): void {
    this.accountListeners.add(listener);
  }

  unsubscribeAccount(listener: () => void): void {
    this.accountListeners.delete(listener);
  }

  publishAccount(): void {
    this.accountListeners.forEach((listener: () => void) => listener());
  }

  private setStorageError(message: string): void {
    if (this.storageError === message) {
      return;
    }
    this.storageError = message;
    this.storageListeners.forEach((listener: () => void) => listener());
  }
  private saveTimer: number = -1;

  @Trace themeMode: ThemeMode = ThemeMode.System;
  @Trace accentPalette: AccentPalette = 'ember';
  @Trace startPage: StartPage = 'home';
  @Trace homeSite: SiteId = 'huya';
  @Trace categorySite: SiteId = 'huya';
  @Trace autoFullscreen: boolean = false;
  @Trace capAt1080: boolean = false;
  @Trace autoSwitchLine: boolean = true;
  @Trace leaveBehavior: LeaveBehavior = 'pip';
  @Trace playerEngine: PlayerEngineChoice = 'ijk';
  @Trace videoFill: boolean = false;
  @Trace volumeMode: VolumeMode = 'media';
  @Trace appVolume: number = 1;
  @Trace danmakuOn: boolean = true;
  @Trace danmakuSize: number = 20;
  @Trace danmakuOpacity: number = 0.85;
  @Trace danmakuArea: number = 0.5;
  @Trace danmakuSpeed: number = 1.0;
  @Trace danmakuStroke: DanmakuStroke = 'stroke';
  @Trace danmakuKeepColor: boolean = true;
  @Trace danmakuMax: number = 60;
  @Trace theaterPanelOpen: boolean = true;
  @Trace sideChat: boolean = false;
  @Trace showSuperChat: boolean = true;
  @Trace blockWords: string[] = [];
  @Trace searchHistory: string[] = [];
  /** Pinned sub-categories encoded as siteId|id|parentId|name|pic. */
  @Trace favCategories: string[] = [];
  @Trace heroAutoPlay: boolean = false;
  /** Transient migration only; never write a session to the settings snapshot. */
  legacyBiliCookie: string = '';
  @Trace biliUid: number = 0;
  @Trace biliName: string = '';
  /** The restored Bilibili login was rejected; keep the prompt across restarts. */
  @Trace biliExpired: boolean = false;
  @Trace accountError: string = '';

  load(ctx: common.Context): void {
    this.context = ctx;
    try {
      this.store = preferences.getPreferencesSync(ctx, { name: 'lumen_settings' });
      this.setStorageError('');
      const raw = this.store.getSync('data', '') as string;
      if (raw.length === 0) {
        return;
      }
      let d: LegacySettingsData;
      try {
        d = JSON.parse(raw) as LegacySettingsData;
      } catch (e) {
        // A previous version stored the Bilibili cookie in this JSON. Even a truncated
        // snapshot must not leave that plaintext on disk indefinitely.
        this.store.putSync('data', '{}');
        this.store.flushSync();
        Log.w('settings', 'Discarded malformed settings');
        return;
      }
      const def = new SettingsData();
      this.loading = true;
      const list = (v: string[] | undefined, fb: string[]): string[] =>
        Array.isArray(v) ? v.filter((x: string) => typeof x === 'string') : fb.slice();
      const num = (v: number | undefined, lo: number, hi: number, fb: number): number =>
        typeof v === 'number' && isFinite(v) && v >= lo && v <= hi ? v : fb;
      const bool = (v: boolean | undefined, fb: boolean): boolean => typeof v === 'boolean' ? v : fb;
      this.themeMode = num(d.themeMode, ThemeMode.System, ThemeMode.Dark, def.themeMode) as ThemeMode;
      const palette = d.accentPalette ?? def.accentPalette;
      this.accentPalette = palette === 'ocean' || palette === 'mint' || palette === 'orchid' ? palette : 'ember';
      const pages: string[] = ['home', 'follow', 'category', 'mine', 'history'];
      this.startPage = pages.indexOf(d.startPage ?? '') >= 0 ? (d.startPage as StartPage) : (def.startPage as StartPage);
      this.homeSite = Sites.isSiteId(d.homeSite ?? '') ? (d.homeSite as SiteId) : (def.homeSite as SiteId);
      this.categorySite =
        Sites.isSiteId(d.categorySite ?? '') ? (d.categorySite as SiteId) : (def.categorySite as SiteId);
      this.autoFullscreen = bool(d.autoFullscreen, def.autoFullscreen);
      this.capAt1080 = bool(d.capAt1080, def.capAt1080);
      this.autoSwitchLine = bool(d.autoSwitchLine, def.autoSwitchLine);
      const leave = d.leaveBehavior ?? def.leaveBehavior;
      this.leaveBehavior = leave === 'audio' || leave === 'pip' ? leave : 'pause';
      this.playerEngine = d.playerEngine === 'avplayer' ? 'avplayer' : 'ijk';
      this.videoFill = bool(d.videoFill, def.videoFill);
      this.volumeMode = d.volumeMode === 'app' ? 'app' : 'media';
      this.appVolume = num(d.appVolume, 0, 1, def.appVolume);
      this.danmakuOn = bool(d.danmakuOn, def.danmakuOn);
      this.danmakuSize = num(d.danmakuSize, 14, 36, def.danmakuSize);
      this.danmakuOpacity = num(d.danmakuOpacity, 0.2, 1, def.danmakuOpacity);
      this.danmakuArea = num(d.danmakuArea, 0.25, 1, def.danmakuArea);
      this.danmakuSpeed = num(d.danmakuSpeed, 0.5, 2, def.danmakuSpeed);
      this.danmakuStroke = d.danmakuStroke === 'shadow' || d.danmakuStroke === 'none' ?
        d.danmakuStroke : 'stroke';
      this.danmakuKeepColor = bool(d.danmakuKeepColor, def.danmakuKeepColor);
      this.danmakuMax = num(d.danmakuMax, 20, 150, def.danmakuMax);
      this.theaterPanelOpen = bool(d.theaterPanelOpen, def.theaterPanelOpen);
      this.sideChat = bool(d.sideChat, def.sideChat);
      this.showSuperChat = bool(d.showSuperChat, def.showSuperChat);
      this.blockWords = list(d.blockWords, def.blockWords);
      this.searchHistory = list(d.searchHistory, def.searchHistory);
      this.favCategories = list(d.favCategories, def.favCategories);
      this.heroAutoPlay = bool(d.heroAutoPlay, def.heroAutoPlay);
      this.legacyBiliCookie = d.biliCookie ?? '';
      this.biliUid = num(d.biliUid, 0, Number.MAX_SAFE_INTEGER, def.biliUid);
      this.biliName = typeof d.biliName === 'string' ? d.biliName : def.biliName;
      this.biliExpired = bool(d.biliExpired, def.biliExpired);
    } catch (e) {
      if (this.unavailableBase === null) {
        this.unavailableBase = this.snapshot();
      }
      this.store = null;
      this.setStorageError('设置存储不可用，请重试');
      Log.e('settings', 'settings storage unavailable');
    } finally {
      this.loading = false;
    }
  }

  retryStorage(): void {
    if (this.store === null && this.context !== null) {
      const base = this.unavailableBase;
      const pending = base === null ? null : this.snapshot();
      this.load(this.context);
      if (this.store === null || base === null || pending === null) {
        return;
      }
      // Read the disk snapshot first, then restore only fields edited while it was unavailable.
      // Never replace a snapshot we could not read at startup with all default values.
      this.mergeUnavailableEdits(base, pending);
      this.unavailableBase = null;
      this.flush().catch(() => {});
    } else if (this.store !== null) {
      this.flush().catch(() => {});
    }
  }

  private mergeUnavailableEdits(base: SettingsData, pending: SettingsData): void {
    if (pending.themeMode !== base.themeMode) this.themeMode = pending.themeMode as ThemeMode;
    if (pending.accentPalette !== base.accentPalette) this.accentPalette = pending.accentPalette as AccentPalette;
    if (pending.startPage !== base.startPage) this.startPage = pending.startPage as StartPage;
    if (pending.homeSite !== base.homeSite) this.homeSite = pending.homeSite as SiteId;
    if (pending.categorySite !== base.categorySite) this.categorySite = pending.categorySite as SiteId;
    if (pending.autoFullscreen !== base.autoFullscreen) this.autoFullscreen = pending.autoFullscreen;
    if (pending.capAt1080 !== base.capAt1080) this.capAt1080 = pending.capAt1080;
    if (pending.autoSwitchLine !== base.autoSwitchLine) this.autoSwitchLine = pending.autoSwitchLine;
    if (pending.leaveBehavior !== base.leaveBehavior) this.leaveBehavior = pending.leaveBehavior as LeaveBehavior;
    if (pending.playerEngine !== base.playerEngine) this.playerEngine = pending.playerEngine as PlayerEngineChoice;
    if (pending.videoFill !== base.videoFill) this.videoFill = pending.videoFill;
    if (pending.volumeMode !== base.volumeMode) this.volumeMode = pending.volumeMode as VolumeMode;
    if (pending.appVolume !== base.appVolume) this.appVolume = pending.appVolume;
    if (pending.danmakuOn !== base.danmakuOn) this.danmakuOn = pending.danmakuOn;
    if (pending.danmakuSize !== base.danmakuSize) this.danmakuSize = pending.danmakuSize;
    if (pending.danmakuOpacity !== base.danmakuOpacity) this.danmakuOpacity = pending.danmakuOpacity;
    if (pending.danmakuArea !== base.danmakuArea) this.danmakuArea = pending.danmakuArea;
    if (pending.danmakuSpeed !== base.danmakuSpeed) this.danmakuSpeed = pending.danmakuSpeed;
    if (pending.danmakuStroke !== base.danmakuStroke) this.danmakuStroke = pending.danmakuStroke as DanmakuStroke;
    if (pending.danmakuKeepColor !== base.danmakuKeepColor) this.danmakuKeepColor = pending.danmakuKeepColor;
    if (pending.danmakuMax !== base.danmakuMax) this.danmakuMax = pending.danmakuMax;
    if (pending.theaterPanelOpen !== base.theaterPanelOpen) this.theaterPanelOpen = pending.theaterPanelOpen;
    if (pending.sideChat !== base.sideChat) this.sideChat = pending.sideChat;
    if (pending.showSuperChat !== base.showSuperChat) this.showSuperChat = pending.showSuperChat;
    if (JSON.stringify(pending.blockWords) !== JSON.stringify(base.blockWords)) {
      this.blockWords = pending.blockWords.slice();
    }
    if (JSON.stringify(pending.searchHistory) !== JSON.stringify(base.searchHistory)) {
      this.searchHistory = pending.searchHistory.slice();
    }
    if (JSON.stringify(pending.favCategories) !== JSON.stringify(base.favCategories)) {
      this.favCategories = pending.favCategories.slice();
    }
    if (pending.heroAutoPlay !== base.heroAutoPlay) this.heroAutoPlay = pending.heroAutoPlay;
    if (pending.biliUid !== base.biliUid) this.biliUid = pending.biliUid;
    if (pending.biliName !== base.biliName) this.biliName = pending.biliName;
    if (pending.biliExpired !== base.biliExpired) this.biliExpired = pending.biliExpired;
  }

  private snapshot(): SettingsData {
    const d = new SettingsData();
    d.themeMode = this.themeMode;
    d.accentPalette = this.accentPalette;
    d.startPage = this.startPage;
    d.homeSite = this.homeSite;
    d.categorySite = this.categorySite;
    d.autoFullscreen = this.autoFullscreen;
    d.capAt1080 = this.capAt1080;
    d.autoSwitchLine = this.autoSwitchLine;
    d.leaveBehavior = this.leaveBehavior;
    d.playerEngine = this.playerEngine;
    d.videoFill = this.videoFill;
    d.volumeMode = this.volumeMode;
    d.appVolume = this.appVolume;
    d.danmakuOn = this.danmakuOn;
    d.danmakuSize = this.danmakuSize;
    d.danmakuOpacity = this.danmakuOpacity;
    d.danmakuArea = this.danmakuArea;
    d.danmakuSpeed = this.danmakuSpeed;
    d.danmakuStroke = this.danmakuStroke;
    d.danmakuKeepColor = this.danmakuKeepColor;
    d.danmakuMax = this.danmakuMax;
    d.theaterPanelOpen = this.theaterPanelOpen;
    d.sideChat = this.sideChat;
    d.showSuperChat = this.showSuperChat;
    d.blockWords = this.blockWords.slice();
    d.searchHistory = this.searchHistory.slice();
    d.favCategories = this.favCategories.slice();
    d.heroAutoPlay = this.heroAutoPlay;
    d.biliUid = this.biliUid;
    d.biliName = this.biliName;
    d.biliExpired = this.biliExpired;
    return d;
  }

  /** Debounces preference writes; call after mutations to this process-wide singleton. */
  scheduleSave(): void {
    if (this.loading) {
      return;
    }
    if (this.store === null) {
      this.setStorageError('设置尚未保存，请重试打开存储');
      return;
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.flush().catch(() => {});
    }, 300);
  }

  async flush(): Promise<void> {
    const s = this.store;
    if (s === null) {
      this.setStorageError('设置尚未保存，请重试打开存储');
      throw new Error('Settings storage unavailable');
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    try {
      s.putSync('data', JSON.stringify(this.snapshot()));
      await s.flush();
      this.setStorageError('');
    } catch (e) {
      this.setStorageError('设置保存失败，请重试');
      Log.e('settings', 'save failed');
      throw new Error('Settings save failed');
    }
  }

  flushOnExit(): void {
    if (this.store === null) {
      return;
    }
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    try {
      this.store.putSync('data', JSON.stringify(this.snapshot()));
      this.store.flushSync();
    } catch (e) {
      Log.e('settings', 'final save failed');
    }
  }

  addSearchHistory(kw: string): void {
    const k = kw.trim();
    if (k.length === 0) {
      return;
    }
    const next = this.searchHistory.filter((x: string) => x !== k);
    next.unshift(k);
    this.searchHistory = next.slice(0, 20);
    this.scheduleSave();
  }
}
