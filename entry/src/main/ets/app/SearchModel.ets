import { AnchorPage, LiveAnchorItem, LiveRoomItem, RoomPage, SiteId } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { RoomFeed } from './RoomFeed';
import { Settings } from './Settings';
import { Log } from '../util/Log';

export type SearchMode = 'room' | 'anchor';

/** Per-platform slice of an aggregated search. */
@ObservedV2
export class SiteResult {
  siteId: SiteId = 'huya';
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace rooms: LiveRoomItem[] = [];
  @Trace anchors: LiveAnchorItem[] = [];
  @Trace hasMore: boolean = false;
  /** Resync this row without replacing the other platform rows. */
  @Trace revision: number = 0;

  constructor(siteId: SiteId) {
    this.siteId = siteId;
  }

  get count(): number {
    return this.rooms.length + this.anchors.length;
  }
}

/** Aggregated three-platform search; results stream in per site as each request returns. */
@ObservedV2
export class SearchModel {
  static readonly inst: SearchModel = new SearchModel();

  @Trace keyword: string = '';
  @Trace mode: SearchMode = 'room';
  @Trace filter: string = 'all';
  @Trace results: SiteResult[] = [];
  @Trace searched: boolean = false;
  /** Full paged feed used when a single platform is selected in room mode. */
  @Trace feed: RoomFeed | null = null;
  /** Views explicitly resync the shared model; per-site revisions keep their row identities. */
  onUpdate: (() => void) | null = null;
  private seq: number = 0;
  private lastSearchAt: number = 0;
  private submittedMode: SearchMode = 'room';
  private feedCache: Map<string, RoomFeed> = new Map<string, RoomFeed>();
  private staleFeeds: Set<string> = new Set<string>();

  private notify(): void {
    this.onUpdate?.();
  }

  search(keyword: string, force: boolean = false): void {
    const kw = keyword.trim();
    if (kw.length === 0) return;
    const same = this.searched && kw === this.keyword && this.mode === this.submittedMode;
    if (same && this.results.some((r: SiteResult) => r.loading)) return;
    if (!force && same && Date.now() - this.lastSearchAt < 15000 &&
      this.results.every((r: SiteResult) => r.error.length === 0)) {
      Settings.inst.addSearchHistory(kw);
      this.notify();
      return;
    }
    if (!same) {
      this.feedCache.clear();
      this.staleFeeds.clear();
      this.results = Sites.ids.map((id: SiteId) => new SiteResult(id));
    } else {
      // Refresh the displayed feed now; other cached filters refresh when next displayed.
      this.feedCache.forEach((_feed: RoomFeed, site: string) => this.staleFeeds.add(site));
    }
    this.lastSearchAt = Date.now();
    this.keyword = kw;
    this.submittedMode = this.mode;
    this.searched = true;
    Settings.inst.addSearchHistory(kw);
    const seq = ++this.seq;
    for (const r of this.results) this.runSite(r, kw, this.submittedMode, seq);
    this.rebuildFeed();
    this.notify();
  }

  setMode(m: SearchMode): void {
    if (m === this.mode) return;
    this.mode = m;
    if (this.searched) this.search(this.keyword, true);
    else this.notify();
  }

  setFilter(f: string): void {
    this.filter = f;
    this.rebuildFeed();
    this.notify();
  }

  private rebuildFeed(): void {
    if (this.filter === 'all' || this.mode !== 'room' || !this.searched) {
      this.feed = null;
      return;
    }
    const site = Sites.of(this.filter);
    const kw = this.keyword;
    let feed = this.feedCache.get(this.filter);
    if (feed === undefined) {
      feed = new RoomFeed((page: number): Promise<RoomPage> => site.searchRooms(kw, page));
      this.feedCache.set(this.filter, feed);
      feed.load();
    } else if (this.staleFeeds.delete(this.filter)) {
      feed.load(true);
    }
    this.feed = feed;
  }

  private async runSite(r: SiteResult, kw: string, mode: SearchMode, seq: number): Promise<void> {
    r.loading = true;
    r.error = '';
    r.revision++;
    try {
      const site = Sites.of(r.siteId);
      if (mode === 'room') {
        const page: RoomPage = await site.searchRooms(kw, 1);
        if (seq !== this.seq) return;
        r.rooms = page.items;
        r.hasMore = page.hasMore;
      } else {
        const page: AnchorPage = await site.searchAnchors(kw, 1);
        if (seq !== this.seq) return;
        r.anchors = page.items.slice().sort((a: LiveAnchorItem, b: LiveAnchorItem) =>
          (b.liveStatus ? 1 : 0) - (a.liveStatus ? 1 : 0));
        r.hasMore = page.hasMore;
      }
    } catch (e) {
      Log.w('search', `${r.siteId} failed: ${e}`);
      if (seq === this.seq) r.error = '搜索失败';
    } finally {
      if (seq === this.seq) {
        r.loading = false;
        r.revision++;
        this.notify();
      }
    }
  }

  retry(r: SiteResult): void {
    if (!this.searched || r.loading || this.results.indexOf(r) < 0) return;
    this.runSite(r, this.keyword, this.submittedMode, this.seq);
    this.notify();
  }

  clear(): void {
    this.seq++;
    this.feedCache.clear();
    this.staleFeeds.clear();
    this.keyword = '';
    this.searched = false;
    this.results = [];
    this.feed = null;
    this.notify();
  }
}
