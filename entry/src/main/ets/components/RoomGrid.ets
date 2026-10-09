import { LiveRoomItem } from '../core/model/Models';
import { RoomFeed } from '../app/RoomFeed';
import { C, Layout, Motion, Space } from '../theme/Theme';
import { RoomCard } from './RoomCard';
import { RefreshGlow, RoomCardSkeleton, StateView } from './Basics';
import { AppEnv } from '../app/AppEnv';

/** Fades and lifts its content in once, optionally staggered. */
@ComponentV2
export struct Appear {
  @Param delay: number = 0;
  @Param distance: number = 14;
  @BuilderParam content: () => void;
  @Local shown: boolean = false;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .opacity(this.shown ? 1 : 0)
    .translate({ y: this.shown ? 0 : this.distance })
    .animation({ curve: Motion.smooth, delay: this.delay })
    .onAppear(() => {
      this.shown = true;
    })
  }
}

/**
 * Virtualized multi-column room list with pull-to-refresh, infinite scroll, skeletons and
 * an optional full-width header. Column count adapts to the available width.
 */
@ComponentV2
export struct RoomGrid {
  @Param feed: RoomFeed = new RoomFeed((p: number) => Promise.reject(new Error('no loader')));
  @Param scope: string = 'grid';
  @Param active: boolean = true;
  @Param startOffset: number = 0;
  /** Bumping alignSeq scrolls to alignY at once, so a grid can take over another's position. */
  @Param alignY: number = -1;
  @Param alignSeq: number = 0;
  @Param showSite: boolean = false;
  @Param minCardWidth: number = 236;
  @Param topPadding: number = 0;
  /** Home owns the shared scrolling header and pull-to-refresh above its bounded lists. */
  @Param nested: boolean = false;
  @Param externalRefresh: boolean = false;
  @Param emptyText: string = '这里暂时没有直播';
  /** Optional extra content inset, used to center secondary-page results. */
  @Param inset: number = 0;
  @Param bottomInset: number = Layout.pageBottom;
  @Param rightInset: number = Space.page;
  @BuilderParam header: () => void = this.noHeader;
  @Event onScrollY: (y: number) => void = () => {};
  @Local areaW: number = 0;
  private scroller: ListScroller = new ListScroller();
  private hasBeenActive: boolean = false;

  @Monitor('active')
  onActive(): void {
    if (this.active && !this.hasBeenActive) {
      this.hasBeenActive = true;
      if (this.startOffset > 0) {
        setTimeout((): void => {
          this.scroller.scrollTo({ xOffset: 0, yOffset: this.startOffset });
        }, 0);
      }
    }
  }

  aboutToAppear(): void {
    if (this.active) this.hasBeenActive = true;
  }

  @Monitor('alignSeq')
  onAlign(): void {
    if (this.alignSeq > 0 && this.alignY >= 0) {
      this.hasBeenActive = true;
      this.scroller.scrollTo({ xOffset: 0, yOffset: this.alignY, animation: false });
      this.onScrollY(this.scroller.currentOffset().yOffset);
    }
  }

  @Builder
  noHeader() {
  }

  get columns(): number {
    const w = this.areaW > 0 ? this.areaW : AppEnv.inst.winWidth;
    return Layout.columns(w - this.inset - Space.page - this.rightInset, this.minCardWidth, Space.lg);
  }

  scrollToTop(): void {
    this.scroller.scrollEdge(Edge.Top, { velocity: 2000 });
  }

  @Builder
  footer() {
    Row({ space: 12 }) {
      if (this.feed.loadingMore) {
        LoadingProgress().width(24).height(24).color(C.text3)
      } else if (this.feed.pageError.length > 0) {
        Text('加载失败').fontSize(12).fontColor(C.text3)
        Text('重试')
          .fontSize(13).fontColor(C.accent).height(40)
          .onClick(() => this.feed.retryMore())
      } else if (!this.feed.hasMore && this.feed.items.length > 0) {
        Text('· 已经到底了 ·').fontSize(12).fontColor(C.text3)
      }
    }
    .width('100%')
    .height(72)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  headerWrap() {
    Column() { this.header() }
      .width('100%')
      .padding({ top: this.topPadding })
  }

  @Builder
  gridList() {
    List({ scroller: this.scroller, space: Space.xl }) {
      ListItemGroup({ header: this.headerWrap(), footer: this.footer(), space: Space.xl }) {
        if (this.feed.initialLoading && this.feed.items.length === 0) {
          ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
            ListItem() { RoomCardSkeleton() }
          }, (i: number) => `sk_${i}`)
        } else if (this.feed.items.length === 0) {
          ListItem() {
            StateView({
              icon: this.feed.error.length > 0 ? $r('sys.symbol.exclamationmark_message') :
                $r('sys.symbol.dot_radiowaves_left_and_right'),
              title: this.feed.error.length > 0 ? '加载失败' : this.emptyText,
              subtitle: this.feed.error,
              actionText: this.feed.error.length > 0 ? '重试' : '',
              onAction: () => this.feed.load()
            })
              .width('100%')
          }
        } else {
          Repeat<LiveRoomItem>(this.feed.items)
            .each((ri: RepeatItem<LiveRoomItem>) => {
              ListItem() {
                if (this.scope.startsWith('home_')) {
                  // Retained home grids must not replay row entrance fades on each site switch.
                  RoomCard({ item: ri.item, scope: this.scope, showSite: this.showSite })
                } else {
                  Appear({ delay: ri.index < 12 ? ri.index * 30 : 0 }) {
                    RoomCard({ item: ri.item, scope: this.scope, showSite: this.showSite })
                  }
                }
              }
            })
            .key((it: LiveRoomItem) => `${this.feed.generation}_${it.siteId}_${it.roomId}`)
            .virtualScroll()
        }
      }
    }
    .lanes(this.feed.items.length === 0 && !this.feed.initialLoading ? 1 : this.columns, Space.lg)
    .width('100%')
    .height('100%')
    .padding({ left: Space.page + this.inset, right: this.rightInset })
    .contentEndOffset(this.bottomInset)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .cachedCount(6)
    .onScrollIndex((start: number, end: number) => {
      if (this.active && end >= this.feed.items.length - this.columns * 3) this.feed.loadMore();
    })
    .onReachEnd(() => {
      if (this.active) this.feed.loadMore();
    })
    .nestedScroll({
      scrollForward: this.nested ? NestedScrollMode.PARENT_FIRST : NestedScrollMode.SELF_ONLY,
      scrollBackward: this.nested ? NestedScrollMode.SELF_FIRST : NestedScrollMode.SELF_ONLY
    })
    .onDidScroll(() => this.onScrollY(this.scroller.currentOffset().yOffset))
    .onAreaChange((_old: Area, area: Area) => { this.areaW = area.width as number; })
  }

  build() {
    if (this.externalRefresh) {
      this.gridList()
    } else {
      Refresh({ refreshing: this.feed.refreshing, builder: this.refreshIndicator() }) {
        this.gridList()
      }
      .onRefreshing(() => this.feed.load(true))
      .refreshOffset(64)
    }
  }

  @Builder
  refreshIndicator() {
    RefreshGlow({ refreshing: this.feed.refreshing })
  }
}
