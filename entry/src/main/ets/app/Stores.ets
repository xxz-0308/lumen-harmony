import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { LiveRoomDetail, LiveRoomItem, SiteId } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { Log } from '../util/Log';

export enum LiveState {
  Unknown = 0,
  Live = 1,
  Offline = 2,
  Replay = 3
}

class FollowData {
  siteId: string = '';
  roomId: string = '';
  userName: string = '';
  avatar: string = '';
  addTime: number = 0;
  tag: string = '';
}

class HistoryData {
  siteId: string = '';
  roomId: string = '';
  userName: string = '';
  avatar: string = '';
  title: string = '';
  cover: string = '';
  area: string = '';
  watchedAt: number = 0;
}

/** A followed anchor plus its last known live snapshot. */
@ObservedV2
export class FollowItem {
  siteId: SiteId = 'huya';
  roomId: string = '';
  addTime: number = 0;
  @Trace userName: string = '';
  @Trace avatar: string = '';
  @Trace tag: string = '';
  @Trace state: LiveState = LiveState.Unknown;
  @Trace title: string = '';
  @Trace cover: string = '';
  @Trace online: number = 0;
  @Trace area: string = '';
  @Trace startTime: number = 0;
  @Trace refreshing: boolean = false;

  get key(): string {
    return `${this.siteId}_${this.roomId}`;
  }

  get isLive(): boolean {
    return this.state === LiveState.Live;
  }

  toRoomItem(): LiveRoomItem {
    const r = LiveRoomItem.of(this.siteId, this.roomId, this.title, this.cover, this.userName, this.online);
    r.avatar = this.avatar;
    r.area = this.area;
    return r;
  }
}

@ObservedV2
export class HistoryItem {
  siteId: SiteId = 'huya';
  roomId: string = '';
  @Trace userName: string = '';
  @Trace avatar: string = '';
  @Trace title: string = '';
  @Trace cover: string = '';
  @Trace area: string = '';
  @Trace watchedAt: number = 0;

  get key(): string {
    return `${this.siteId}_${this.roomId}`;
  }

  toRoomItem(): LiveRoomItem {
    const r = LiveRoomItem.of(this.siteId, this.roomId, this.title, this.cover, this.userName, 0);
    r.avatar = this.avatar;
    r.area = this.area;
    return r;
  }
}

function openPrefs(ctx: common.Context, name: string): preferences.Preferences | null {
  try {
    return preferences.getPreferencesSync(ctx, { name: name });
  } catch (e) {
    Log.e('store', `open ${name} failed ${JSON.stringify(e)}`);
    return null;
  }
}

@ObservedV2
export class FollowStore {
  static readonly inst: FollowStore = new FollowStore();
  private prefs: preferences.Preferences | null = null;
  private lastRefresh: number = 0;
  private refreshSeq: number = 0;
  private pendingRefresh: boolean = false;
  private listeners: Set<() => void> = new Set<() => void>();

  @Trace items: FollowItem[] = [];
  @Trace refreshing: boolean = false;
  @Trace lastRefreshAt: number = 0;
  @Trace refreshFailures: number = 0;
  @Trace storageError: string = '';
  @Trace saveError: string = '';

  subscribe(listener: () => void): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: () => void): void {
    this.listeners.delete(listener);
  }

  private notify(): void {
    this.listeners.forEach((listener: () => void) => listener());
  }

  load(ctx: common.Context): void {
    this.prefs = openPrefs(ctx, 'lumen_follows');
    if (this.prefs === null) {
      this.storageError = '关注存储暂不可用，本次修改无法保存';
      this.notify();
      return;
    }
    try {
      const raw = this.prefs.getSync('list', '[]') as string;
      const list = JSON.parse(raw) as FollowData[];
      const out: FollowItem[] = [];
      const seen = new Set<string>();
      for (const d of list) {
        if (!Sites.isSiteId(d.siteId) || typeof d.roomId !== 'string' || d.roomId.length === 0) {
          continue;
        }
        const key = `${d.siteId}_${d.roomId}`;
        if (seen.has(key)) {
          continue;
        }
        seen.add(key);
        const f = new FollowItem();
        f.siteId = d.siteId as SiteId;
        f.roomId = d.roomId;
        f.userName = d.userName;
        f.avatar = d.avatar;
        f.addTime = d.addTime;
        f.tag = d.tag ?? '';
        out.push(f);
      }
      this.items = out;
      this.storageError = '';
      this.notify();
    } catch (e) {
      this.storageError = '关注数据读取失败，原记录未被覆盖';
      Log.e('follow', `load ${JSON.stringify(e)}`);
      this.notify();
    }
  }

  private persist(): void {
    if (this.prefs === null || this.storageError.length > 0) {
      return;
    }
    const list: FollowData[] = this.items.map((f: FollowItem) => {
      const d = new FollowData();
      d.siteId = f.siteId;
      d.roomId = f.roomId;
      d.userName = f.userName;
      d.avatar = f.avatar;
      d.addTime = f.addTime;
      d.tag = f.tag;
      return d;
    });
    try {
      this.prefs.putSync('list', JSON.stringify(list));
      this.prefs.flush().then(() => {
        this.saveError = '';
        this.notify();
      }).catch(() => {
        this.saveError = '关注保存失败，请重试';
        this.notify();
        Log.w('store', 'follow flush failed');
      });
    } catch (e) {
      this.saveError = '关注保存失败，请重试';
      this.notify();
      Log.e('follow', `save ${JSON.stringify(e)}`);
    }
  }

  find(siteId: string, roomId: string): FollowItem | undefined {
    return this.items.find((f: FollowItem) => f.siteId === siteId && f.roomId === roomId);
  }

  isFollowed(siteId: string, roomId: string): boolean {
    return this.find(siteId, roomId) !== undefined;
  }

  follow(detail: LiveRoomDetail): void {
    if (this.storageError.length > 0 || this.isFollowed(detail.siteId, detail.roomId)) {
      return;
    }
    const f = new FollowItem();
    f.siteId = detail.siteId;
    f.roomId = detail.roomId;
    f.userName = detail.userName;
    f.avatar = detail.userAvatar;
    f.addTime = Date.now();
    FollowStore.applyDetail(f, detail);
    this.items = [f].concat(this.items);
    this.notify();
    this.persist();
  }

  followAnchor(siteId: SiteId, roomId: string, userName: string, avatar: string, live: boolean): void {
    if (this.storageError.length > 0 || this.isFollowed(siteId, roomId)) {
      return;
    }
    const f = new FollowItem();
    f.siteId = siteId;
    f.roomId = roomId;
    f.userName = userName;
    f.avatar = avatar;
    f.addTime = Date.now();
    f.state = live ? LiveState.Live : LiveState.Offline;
    this.items = [f].concat(this.items);
    this.notify();
    this.persist();
    this.refreshOne(f);
  }

  unfollow(siteId: string, roomId: string): void {
    if (this.storageError.length > 0) {
      return;
    }
    this.items = this.items.filter((f: FollowItem) => !(f.siteId === siteId && f.roomId === roomId));
    this.notify();
    this.persist();
  }

  /** Called when a room page loads so the follow card reflects fresh data immediately. */
  updateFromDetail(detail: LiveRoomDetail): void {
    const f = this.find(detail.siteId, detail.roomId);
    if (f === undefined) {
      return;
    }
    const changed = f.userName !== detail.userName || f.avatar !== detail.userAvatar;
    FollowStore.applyDetail(f, detail);
    this.notify();
    if (changed) {
      f.userName = detail.userName;
      f.avatar = detail.userAvatar;
      this.persist();
    }
  }

  private static applyDetail(f: FollowItem, d: LiveRoomDetail): void {
    f.state = d.status ? LiveState.Live : (d.isRecord ? LiveState.Replay : LiveState.Offline);
    f.title = d.title;
    f.cover = d.cover;
    f.online = d.online;
    f.area = d.area;
    f.startTime = d.startTime;
    if (d.userAvatar.length > 0) {
      f.avatar = d.userAvatar;
    }
  }

  get liveItems(): FollowItem[] {
    return this.items.filter((f: FollowItem) => f.isLive).sort((a: FollowItem, b: FollowItem) => b.online - a.online);
  }

  /** Live first (by popularity), then replay, then offline/unknown by follow time. */
  get sorted(): FollowItem[] {
    const rank = (f: FollowItem): number => f.state === LiveState.Live ? 0 : f.state === LiveState.Replay ? 1 : 2;
    return this.items.slice().sort((a: FollowItem, b: FollowItem) => {
      const r = rank(a) - rank(b);
      if (r !== 0) {
        return r;
      }
      if (a.isLive) {
        return b.online - a.online;
      }
      return b.addTime - a.addTime;
    });
  }

  private async refreshOne(f: FollowItem): Promise<void> {
    f.refreshing = true;
    try {
      const d = await Sites.of(f.siteId).getRoomDetail(f.roomId);
      FollowStore.applyDetail(f, d);
      if (f.userName.length === 0 || f.userName !== d.userName) {
        f.userName = d.userName;
      }
    } catch (e) {
      this.refreshFailures++;
      Log.w('follow', `refresh ${f.key} failed: ${e}`);
    } finally {
      f.refreshing = false;
      this.notify();
    }
  }

  /** Refreshes every follow with bounded concurrency; `force` bypasses the 60s throttle. */
  async refreshAll(force: boolean = false): Promise<void> {
    const now = Date.now();
    if (this.refreshing) {
      // A user-initiated refresh during a sweep queues one follow-up instead of vanishing.
      if (force) {
        this.pendingRefresh = true;
      }
      return;
    }
    if (!force && now - this.lastRefresh < 60 * 1000) {
      return;
    }
    this.lastRefresh = now;
    this.refreshing = true;
    this.refreshFailures = 0;
    this.notify();
    const seq = ++this.refreshSeq;
    const queue = this.items.slice();
    const worker = async (): Promise<void> => {
      while (queue.length > 0 && seq === this.refreshSeq) {
        const f = queue.shift();
        if (f !== undefined) {
          await this.refreshOne(f);
        }
      }
    };
    const workers: Promise<void>[] = [];
    for (let i = 0; i < 4; i++) {
      workers.push(worker());
    }
    await Promise.all(workers);
    if (seq === this.refreshSeq) {
      this.refreshing = false;
      this.lastRefreshAt = Date.now();
      // Partial failures should not suppress the next automatic check for a whole minute.
      if (this.refreshFailures > 0) {
        this.lastRefresh = Date.now() - 45000;
      }
      this.notify();
      this.persist();
      if (this.pendingRefresh) {
        this.pendingRefresh = false;
        this.refreshAll(true).catch(() => {});
      }
    }
  }
}

@ObservedV2
export class HistoryStore {
  static readonly inst: HistoryStore = new HistoryStore();
  private prefs: preferences.Preferences | null = null;
  private listeners: Set<() => void> = new Set<() => void>();

  @Trace items: HistoryItem[] = [];
  @Trace storageError: string = '';
  @Trace saveError: string = '';

  subscribe(listener: () => void): void {
    this.listeners.add(listener);
  }

  unsubscribe(listener: () => void): void {
    this.listeners.delete(listener);
  }

  private notify(): void {
    this.listeners.forEach((listener: () => void) => listener());
  }

  load(ctx: common.Context): void {
    this.prefs = openPrefs(ctx, 'lumen_history');
    if (this.prefs === null) {
      this.storageError = '历史存储暂不可用，本次记录无法保存';
      this.notify();
      return;
    }
    try {
      const list = JSON.parse(this.prefs.getSync('list', '[]') as string) as HistoryData[];
      if (!Array.isArray(list)) {
        throw new Error('Invalid history list');
      }
      const out: HistoryItem[] = [];
      for (const d of list) {
        if (d === null || typeof d !== 'object' || !Sites.isSiteId(d.siteId) ||
          typeof d.roomId !== 'string' || d.roomId.trim().length === 0 ||
          typeof d.watchedAt !== 'number' || !Number.isFinite(d.watchedAt) || d.watchedAt <= 0) {
          continue;
        }
        const h = new HistoryItem();
        h.siteId = d.siteId as SiteId;
        h.roomId = d.roomId.trim();
        h.userName = typeof d.userName === 'string' ? d.userName : '';
        h.avatar = typeof d.avatar === 'string' ? d.avatar : '';
        h.title = typeof d.title === 'string' ? d.title : '';
        h.cover = typeof d.cover === 'string' ? d.cover : '';
        h.area = typeof d.area === 'string' ? d.area : '';
        h.watchedAt = d.watchedAt;
        out.push(h);
      }
      out.sort((a: HistoryItem, b: HistoryItem) => b.watchedAt - a.watchedAt);
      const seen = new Set<string>();
      this.items = out.filter((h: HistoryItem) => {
        const key = `${h.siteId}:${h.roomId}`;
        if (seen.has(key)) {
          return false;
        }
        seen.add(key);
        return true;
      }).slice(0, 200);
      this.storageError = '';
      this.notify();
    } catch (e) {
      this.storageError = '历史数据读取失败，原记录未被覆盖';
      Log.e('history', `load ${JSON.stringify(e)}`);
      this.notify();
    }
  }

  private persist(): void {
    if (this.prefs === null || this.storageError.length > 0) {
      return;
    }
    const list: HistoryData[] = this.items.map((h: HistoryItem) => {
      const d = new HistoryData();
      d.siteId = h.siteId;
      d.roomId = h.roomId;
      d.userName = h.userName;
      d.avatar = h.avatar;
      d.title = h.title;
      d.cover = h.cover;
      d.area = h.area;
      d.watchedAt = h.watchedAt;
      return d;
    });
    try {
      this.prefs.putSync('list', JSON.stringify(list));
      this.prefs.flush().then(() => {
        this.saveError = '';
        this.notify();
      }).catch(() => {
        this.saveError = '历史记录保存失败，请重试';
        this.notify();
        Log.w('store', 'history flush failed');
      });
    } catch (e) {
      this.saveError = '历史记录保存失败，请重试';
      this.notify();
      Log.e('history', `save ${JSON.stringify(e)}`);
    }
  }

  record(d: LiveRoomDetail): void {
    if (this.storageError.length > 0) {
      return;
    }
    const h = new HistoryItem();
    h.siteId = d.siteId;
    h.roomId = d.roomId;
    h.userName = d.userName;
    h.avatar = d.userAvatar;
    h.title = d.title;
    h.cover = d.cover;
    h.area = d.area;
    h.watchedAt = Date.now();
    const rest = this.items.filter((x: HistoryItem) => !(x.siteId === d.siteId && x.roomId === d.roomId));
    this.items = [h].concat(rest).slice(0, 200);
    this.notify();
    this.persist();
  }

  remove(siteId: string, roomId: string): void {
    if (this.storageError.length > 0) {
      return;
    }
    this.items = this.items.filter((x: HistoryItem) => !(x.siteId === siteId && x.roomId === roomId));
    this.notify();
    this.persist();
  }

  clear(): void {
    if (this.storageError.length > 0) {
      return;
    }
    this.items = [];
    this.notify();
    this.persist();
  }
}
