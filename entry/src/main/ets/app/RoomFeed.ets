import { LiveRoomItem, RoomPage } from '../core/model/Models';
import { Log } from '../util/Log';

export type PageLoader = (page: number) => Promise<RoomPage>;

/** Paged, de-duplicated room list with refresh/load-more state and stale-response protection. */
@ObservedV2
export class RoomFeed {
  @Trace items: LiveRoomItem[] = [];
  @Trace initialLoading: boolean = false;
  @Trace refreshing: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace error: string = '';
  /** Set when a follow-up page fails while items are already on screen. */
  @Trace pageError: string = '';
  /** Increments on every successful first-page load so views can replay entrance animations. */
  @Trace generation: number = 0;
  private page: number = 0;
  private failedPage: number = 0;
  private seq: number = 0;
  private loader: PageLoader;
  private keys: Set<string> = new Set<string>();

  constructor(loader: PageLoader) {
    this.loader = loader;
  }

  setLoader(loader: PageLoader): void {
    this.loader = loader;
    this.seq++;
    this.items = [];
    this.keys.clear();
    this.page = 0;
    this.failedPage = 0;
    this.hasMore = true;
    this.error = '';
    this.loadingMore = false;
    this.refreshing = false;
  }

  get isEmpty(): boolean {
    return this.items.length === 0;
  }

  async load(pull: boolean = false): Promise<void> {
    const seq = ++this.seq;
    if (pull) {
      this.refreshing = true;
    } else if (this.items.length === 0) {
      this.initialLoading = true;
    }
    this.error = '';
    this.pageError = '';
    // A pull-to-refresh that lands mid-page must not leave the pager latched.
    this.loadingMore = false;
    try {
      const res = await this.loader(1);
      if (seq !== this.seq) {
        return;
      }
      this.keys.clear();
      const fresh: LiveRoomItem[] = [];
      for (const it of res.items) {
        const k = `${it.siteId}_${it.roomId}`;
        if (!this.keys.has(k)) {
          this.keys.add(k);
          fresh.push(it);
        }
      }
      this.items = fresh;
      this.page = 1;
      this.failedPage = 0;
      this.hasMore = res.hasMore && fresh.length > 0;
      this.generation++;
    } catch (e) {
      if (seq === this.seq) {
        const msg = RoomFeed.describe(e);
        this.failedPage = 1;
        Log.w('feed', `load failed: ${e}`);
        if (pull || this.items.length > 0) {
          // Keep the cards that are already on screen; surface the failure separately.
          this.pageError = msg;
        } else {
          this.error = msg;
        }
      }
    } finally {
      if (seq === this.seq) {
        this.initialLoading = false;
        this.refreshing = false;
      }
    }
  }

  /** User-initiated retry after a failed page. */
  retryMore(): void {
    if (this.pageError.length === 0 || this.initialLoading || this.refreshing || this.loadingMore) {
      return;
    }
    if (this.failedPage === 1 || this.page === 0) {
      this.load(this.items.length > 0);
      return;
    }
    this.pageError = '';
    this.hasMore = true;
    this.loadMore();
  }

  async loadMore(): Promise<void> {
    if (this.loadingMore || !this.hasMore || this.initialLoading || this.refreshing || this.page === 0 || this.pageError.length > 0) {
      return;
    }
    const seq = this.seq;
    this.loadingMore = true;
    try {
      const res = await this.loader(this.page + 1);
      if (seq !== this.seq) {
        return;
      }
      const add: LiveRoomItem[] = [];
      for (const it of res.items) {
        const k = `${it.siteId}_${it.roomId}`;
        if (!this.keys.has(k)) {
          this.keys.add(k);
          add.push(it);
        }
      }
      this.page++;
      this.failedPage = 0;
      this.items = this.items.concat(add);
      // some endpoints keep returning the same page; stop when nothing new arrives
      this.hasMore = res.hasMore && add.length > 0;
    } catch (e) {
      Log.w('feed', `loadMore failed: ${e}`);
      if (seq === this.seq) {
        this.failedPage = this.page + 1;
        this.pageError = RoomFeed.describe(e);
        // Stop hammering the endpoint on every scroll until the user retries.
        this.hasMore = false;
      }
    } finally {
      if (seq === this.seq) {
        this.loadingMore = false;
      }
    }
  }

  static describe(e: Object | null | undefined): string {
    const s = `${e}`;
    Log.w('feed', `error: ${s}`);
    if (s.indexOf('HTTP 4') >= 0 || s.indexOf('HTTP 5') >= 0) {
      return '服务暂时不可用，请稍后再试';
    }
    if (s.indexOf('timeout') >= 0 || s.indexOf('Timeout') >= 0 || s.indexOf('2300') >= 0) {
      return '网络超时，请检查网络后重试';
    }
    if (s.indexOf('SyntaxError') >= 0 || s.indexOf('Unexpected') >= 0) {
      return '返回数据异常，请稍后再试';
    }
    // Never surface raw SDK text in the Chinese UI; the detail goes to the log above.
    return '加载失败，请稍后重试';
  }
}
