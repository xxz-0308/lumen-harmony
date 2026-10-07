import { LengthMetrics } from '@kit.ArkUI';
import { FollowItem, FollowStore, LiveState } from '../app/Stores';
import { AppEnv } from '../app/AppEnv';
import { C, formatDuration, Layout, relativeTime, Space } from '../theme/Theme';
import { RoomCard } from '../components/RoomCard';
import { AnchorTile } from '../components/AnchorTile';
import { IconButton, RefreshGlow, StateView } from '../components/Basics';
import { FilterChip, PageTitle, SectionTitle } from '../components/Decor';
import { Appear } from '../components/RoomGrid';
import { SiteStyle } from '../theme/Theme';

const FILTERS: string[] = ['all', 'huya', 'douyu', 'bilibili'];

@ComponentV2
export struct FollowView {
  @Local filter: string = 'all';
  @Local areaW: number = 1100;
  @Local snapshot: FollowItem[] = FollowStore.inst.items;
  @Local refreshing: boolean = FollowStore.inst.refreshing;
  @Local refreshFailures: number = 0;
  @Local storageError: string = '';
  @Local saveError: string = '';
  private syncFollows: () => void = () => {
    this.snapshot = FollowStore.inst.items.slice();
    this.refreshing = FollowStore.inst.refreshing;
    this.refreshFailures = FollowStore.inst.refreshFailures;
    this.storageError = FollowStore.inst.storageError;
    this.saveError = FollowStore.inst.saveError;
  };

  aboutToAppear(): void {
    FollowStore.inst.subscribe(this.syncFollows);
    this.syncFollows();
    FollowStore.inst.refreshAll();
  }

  aboutToDisappear(): void {
    FollowStore.inst.unsubscribe(this.syncFollows);
  }

  get contentW(): number {
    return Math.max(160, this.areaW - Space.page * 2);
  }

  get cardCols(): number {
    return Layout.columns(this.contentW, 236, Space.lg);
  }

  get tileCols(): number {
    return Layout.columns(this.contentW, 260, Space.md);
  }

  cardW(cols: number, gap: number): number {
    return (this.contentW - gap * (cols - 1)) / cols;
  }

  @Computed
  get visible(): FollowItem[] {
    const rank = (f: FollowItem): number => f.state === LiveState.Live ? 0 :
      (f.state === LiveState.Replay ? 1 : 2);
    const all = this.snapshot.slice().sort((a: FollowItem, b: FollowItem) => {
      const order = rank(a) - rank(b);
      return order !== 0 ? order : (a.isLive ? b.online - a.online : b.addTime - a.addTime);
    });
    return this.filter === 'all' ? all : all.filter((f: FollowItem) => f.siteId === this.filter);
  }

  @Computed
  get live(): FollowItem[] {
    return this.visible.filter((f: FollowItem) => f.state === LiveState.Live);
  }

  @Computed
  get rest(): FollowItem[] {
    return this.visible.filter((f: FollowItem) => f.state !== LiveState.Live);
  }

  get subtitle(): string {
    const n = this.snapshot.length;
    if (this.storageError.length > 0) {
      return this.storageError;
    }
    if (n === 0) {
      return '';
    }
    const at = this.refreshing ? '正在刷新' : (FollowStore.inst.lastRefreshAt > 0 ?
      `更新于 ${relativeTime(FollowStore.inst.lastRefreshAt)}` : '');
    const failure = this.refreshFailures > 0 ? ` · ${this.refreshFailures} 位刷新失败，可重试` : '';
    const live = this.snapshot.filter((f: FollowItem) => f.isLive).length;
    return `${n} 位主播 · ${live} 位在直播${at.length > 0 ? ' · ' + at : ''}${failure}${this.saveError ? ' · ' + this.saveError : ''}`;
  }

  countOf(site: string): number {
    return site === 'all' ? this.snapshot.length :
      this.snapshot.filter((f: FollowItem) => f.siteId === site).length;
  }

  @Builder
  trailing() {
    if (this.refreshing) {
      Row() {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(C.text3)
      }
      .height(40)
      .padding({ left: 12, right: 12 })
    } else {
      IconButton({
        icon: $r('sys.symbol.arrow_clockwise'), label: '刷新', onTap: () => {
          this.refreshing = true;
          FollowStore.inst.refreshAll(true);
        }
      })
    }
  }

  build() {
    Refresh({ refreshing: this.refreshing, builder: this.refreshIndicator() }) {
      Scroll() {
        Column({ space: Space.xl }) {
          PageTitle({ title: '关注', subtitle: this.subtitle }) {
            this.trailing()
          }
          if (this.snapshot.length > 0) {
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
              ForEach(FILTERS, (f: string) => {
                FilterChip({
                  label: `${f === 'all' ? '全部' : SiteStyle.label(f)} ${this.countOf(f)}`,
                  selected: this.filter === f,
                  dotColor: f === 'all' ? '' : SiteStyle.color(f),
                  onTap: () => {
                    // Cards of other platforms leave and the rest close up smoothly.
                    this.getUIContext().animateTo({ duration: AppEnv.inst.reduceMotion ? 0 : 260, curve: Curve.EaseInOut }, () => {
                      this.filter = f;
                    });
                  }
                })
              }, (f: string) => f)
            }
          }

          if (this.snapshot.length === 0) {
            StateView({
              icon: $r('sys.symbol.heart'),
              title: this.storageError.length > 0 ? '关注数据暂不可用' : '还没有关注主播',
              subtitle: this.storageError.length > 0 ? this.storageError : '在直播间点「关注」，或在搜索里找到主播一键关注'
            })
              .width('100%')
              .margin({ top: 60 })
          } else if (this.visible.length === 0) {
            StateView({
              icon: $r('sys.symbol.dot_radiowaves_left_and_right'),
              title: '这个平台还没有关注的主播',
              subtitle: '切换到「全部」查看其他平台的关注'
            })
              .width('100%')
              .margin({ top: 60 })
          } else {
            if (this.live.length > 0) {
              SectionTitle({ title: '直播中', subtitle: `${this.live.length}` })
              Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.lg), cross: LengthMetrics.vp(Space.xl) } }) {
                ForEach(this.live, (f: FollowItem, i: number) => {
                  Column() {
                    Appear({ delay: i < 12 ? i * 30 : 0 }) {
                      RoomCard({
                        item: f.toRoomItem(),
                        scope: 'follow',
                        meta: `${f.userName}${f.startTime > 0 ? ' · ' + formatDuration(f.startTime) : ''}`
                      })
                    }
                  }
                  .width(this.cardW(this.cardCols, Space.lg))
                }, (f: FollowItem) => f.key)
              }
            }
            if (this.rest.length > 0) {
              SectionTitle({ title: '未开播', subtitle: `${this.rest.length}` })
                .margin({ top: 8 })
              Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(Space.md), cross: LengthMetrics.vp(Space.md) } }) {
                ForEach(this.rest, (f: FollowItem) => {
                  AnchorTile({
                    siteId: f.siteId,
                    roomId: f.roomId,
                    userName: f.userName,
                    avatar: f.avatar,
                    live: false,
                    subtitle: f.refreshing ? '刷新中…' : (f.state === LiveState.Replay ? '轮播中' :
                      (f.state === LiveState.Unknown ? SiteStyle.label(f.siteId) : `${SiteStyle.label(f.siteId)} · 未开播`))
                  })
                    .width(this.cardW(this.tileCols, Space.md))
                }, (f: FollowItem) => f.key)
              }
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: Space.page,
          right: Space.page,
          top: AppEnv.inst.statusBarHeight + 24,
          bottom: Layout.bottomNavInset
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .onRefreshing(() => {
      FollowStore.inst.refreshAll(true);
    })
    .refreshOffset(64)
    .onAreaChange((o: Area, n: Area) => {
      this.areaW = n.width as number;
    })
  }

  @Builder
  refreshIndicator() {
    RefreshGlow({ refreshing: this.refreshing })
  }
}
