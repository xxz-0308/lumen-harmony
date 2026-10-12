import { LengthMetrics } from '@kit.ArkUI';
import { FollowItem, FollowStore, LiveState } from '../app/Stores';
import { AppEnv } from '../app/AppEnv';
import { NavigationActivity } from '../app/NavigationActivity';
import { C, formatDuration, Layout, relativeTime, Space } from '../theme/Theme';
import { RoomCard } from '../components/RoomCard';
import { AnchorTile } from '../components/AnchorTile';
import { RefreshGlow, StateView } from '../components/Basics';
import { FilterChip, PageTitle, SectionTitle } from '../components/Decor';
import { Appear } from '../components/RoomGrid';
import { SiteStyle } from '../theme/Theme';

const FILTERS: string[] = ['all', 'huya', 'douyu', 'bilibili'];

type FollowRowKind = 'liveHeader' | 'liveRow' | 'restHeader' | 'restRow';

class FollowRow {
  key: string = '';
  kind: FollowRowKind = 'liveRow';
  count: number = 0;
  baseIndex: number = 0;
  items: FollowItem[] = [];
}

@ComponentV2
export struct RefreshIconButton {
  @Param refreshing: boolean = false;
  @Param active: boolean = true;
  @Event onTap: () => void = () => {};
  @Local spinAngle: number = 0;
  @Local pressed: boolean = false;
  @Local env: AppEnv = AppEnv.inst;
  private spinning: boolean = false;
  private timer: number = -1;
  private mounted: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.reconcileSpin();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.stopSpin();
  }

  @Monitor('refreshing', 'active', 'env.foreground', 'env.reduceMotion')
  onSpinState(): void {
    this.reconcileSpin();
  }

  private reconcileSpin(): void {
    if (this.mounted && this.refreshing && this.active && this.env.foreground && !this.env.reduceMotion) {
      this.startSpin();
    } else {
      this.stopSpin();
    }
  }

  private stopSpin(): void {
    this.spinning = false;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private startSpin(): void {
    if (!this.mounted || !this.active || !this.env.foreground || this.spinning || this.env.reduceMotion) return;
    this.spinning = true;
    this.spinAngle += 360;
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.spinning = false;
      if (this.mounted && this.refreshing && this.active && this.env.foreground && !this.env.reduceMotion) {
        this.startSpin();
      }
    }, 620);
  }

  build() {
    Button({ type: ButtonType.Circle }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([C.text1])
      }
      .width(24)
      .height(24)
      .rotate({ centerX: '50%', centerY: '50%', angle: this.spinAngle })
      .animation({ duration: AppEnv.inst.reduceMotion ? 0 : 600, curve: Curve.EaseInOut })
    }
    .width(44)
    .height(44)
    .backgroundColor(this.pressed ? C.surface3 : Color.Transparent)
    .scale({ x: this.pressed && !AppEnv.inst.reduceMotion ? 0.94 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.94 : 1 })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .accessibilityText('刷新')
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.startSpin();
      this.onTap();
    })
  }
}

@ComponentV2
export struct FollowView {
  @Param active: boolean = true;
  @Local navActivity: NavigationActivity = NavigationActivity.inst;
  @Local env: AppEnv = AppEnv.inst;
  @Local filter: string = 'all';
  @Local areaW: number = 1100;
  @Local snapshot: FollowItem[] = [];
  @Local refreshing: boolean = FollowStore.inst.refreshing;
  @Local pullRefreshing: boolean = false;
  @Local refreshFailures: number = 0;
  @Local storageError: string = '';
  @Local saveError: string = '';
  @Local updatedAt: number = 0;
  private mounted: boolean = false;
  private contentRevision: number = -1;
  private pullStartedAt: number = 0;
  private pullEndTimer: number = -1;
  private syncFollows: () => void = () => {
    if (!this.mounted || !this.running) return;
    const store = FollowStore.inst;
    if (this.contentRevision !== store.contentRevision) {
      this.snapshot = store.items.map((f: FollowItem) => f.snapshot());
      this.contentRevision = store.contentRevision;
    }
    this.refreshing = store.refreshing;
    if (!store.refreshing && this.pullRefreshing) {
      const waitMs = 220 - (Date.now() - this.pullStartedAt);
      if (waitMs <= 0) {
        this.pullRefreshing = false;
      } else if (this.pullEndTimer === -1) {
        this.pullEndTimer = setTimeout(() => {
          this.pullEndTimer = -1;
          this.pullRefreshing = false;
        }, waitMs);
      }
    }
    this.refreshFailures = store.refreshFailures;
    this.storageError = store.storageError;
    this.saveError = store.saveError;
    this.updatedAt = store.lastRefreshAt;
  };

  get running(): boolean { return this.active && this.navActivity.rootActive && this.env.foreground; }

  @Monitor('active', 'navActivity.rootActive', 'env.foreground')
  onActive(): void {
    if (this.running) {
      this.syncFollows();
    } else {
      if (this.pullEndTimer !== -1) {
        clearTimeout(this.pullEndTimer);
        this.pullEndTimer = -1;
      }
      this.pullRefreshing = false;
    }
  }

  aboutToAppear(): void {
    this.mounted = true;
    FollowStore.inst.subscribe(this.syncFollows);
    this.syncFollows();
    FollowStore.inst.refreshAll();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    if (this.pullEndTimer !== -1) {
      clearTimeout(this.pullEndTimer);
      this.pullEndTimer = -1;
    }
    FollowStore.inst.unsubscribe(this.syncFollows);
  }

  get contentW(): number {
    return Math.max(160, this.areaW - Space.page * 2);
  }

  get cardCols(): number {
    return Layout.columns(this.contentW, 320, Space.xl);
  }

  get tileCols(): number {
    return Layout.columns(this.contentW, 280, Space.lg);
  }

  cardW(cols: number, gap: number): number {
    return (this.contentW - gap * (cols - 1)) / cols;
  }

  private cardKey(f: FollowItem): string {
    return `${f.renderKey}_${f.startTime > 0 ? formatDuration(f.startTime) : ''}`;
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
  get rows(): FollowRow[] {
    const out: FollowRow[] = [];
    const vis = this.visible;
    const liveList: FollowItem[] = [];
    const restList: FollowItem[] = [];
    for (const f of vis) {
      if (f.state === LiveState.Live) {
        liveList.push(f);
      } else {
        restList.push(f);
      }
    }
    const contentW = Math.max(160, this.areaW - Space.page * 2);
    const cCols = Layout.columns(contentW, 320, Space.xl);
    const tCols = Layout.columns(contentW, 280, Space.lg);
    if (liveList.length > 0) {
      const h = new FollowRow();
      h.kind = 'liveHeader';
      h.count = liveList.length;
      h.key = `hdr_live_${liveList.length}`;
      out.push(h);
      for (let i = 0; i < liveList.length; i += cCols) {
        const slice = liveList.slice(i, i + cCols);
        const r = new FollowRow();
        r.kind = 'liveRow';
        r.baseIndex = i;
        r.items = slice;
        r.key = `live_${cCols}_${i}_${slice.map((f: FollowItem) => this.cardKey(f)).join('_')}`;
        out.push(r);
      }
    }
    if (restList.length > 0) {
      const h = new FollowRow();
      h.kind = 'restHeader';
      h.count = restList.length;
      h.baseIndex = liveList.length > 0 ? 1 : 0;
      h.key = `hdr_rest_${restList.length}_${h.baseIndex}`;
      out.push(h);
      for (let i = 0; i < restList.length; i += tCols) {
        const slice = restList.slice(i, i + tCols);
        const r = new FollowRow();
        r.kind = 'restRow';
        r.baseIndex = i;
        r.items = slice;
        r.key = `rest_${tCols}_${i}_${slice.map((f: FollowItem) => f.renderKey).join('_')}`;
        out.push(r);
      }
    }
    return out;
  }

  get subtitle(): string {
    const n = this.snapshot.length;
    if (this.storageError.length > 0) {
      return this.storageError;
    }
    if (n === 0) {
      return '';
    }
    const at = this.updatedAt > 0 ? `更新于 ${relativeTime(this.updatedAt)}` :
      (this.refreshing ? '正在刷新' : '');
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
    RefreshIconButton({
      refreshing: this.refreshing && !this.pullRefreshing,
      active: this.running,
      onTap: () => {
        FollowStore.inst.refreshAll(true);
      }
    })
  }

  @Builder
  followRowView(row: FollowRow) {
    if (row.kind === 'liveHeader') {
      Row() {
        SectionTitle({ title: '直播中', subtitle: `${row.count}` })
      }
      .width('100%')
      .padding({ bottom: Space.xl })
    } else if (row.kind === 'liveRow') {
      Row({ space: Space.xl }) {
        ForEach(row.items, (f: FollowItem, idx: number) => {
          Column() {
            Appear({ delay: (row.baseIndex + idx) < 12 ? (row.baseIndex + idx) * 30 : 0 }) {
              RoomCard({
                item: f.toRoomItem(),
                scope: 'follow',
                meta: `${f.userName}${f.startTime > 0 ? ' · ' + formatDuration(f.startTime) : ''}`
              })
            }
          }
          .width(this.cardW(this.cardCols, Space.xl))
        }, (f: FollowItem) => this.cardKey(f))
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ bottom: Space.xl })
    } else if (row.kind === 'restHeader') {
      Row() {
        SectionTitle({ title: '未开播', subtitle: `${row.count}` })
      }
      .width('100%')
      .padding({ top: row.baseIndex > 0 ? 8 : 0, bottom: Space.lg })
    } else {
      Row({ space: Space.lg }) {
        ForEach(row.items, (f: FollowItem) => {
          AnchorTile({
            siteId: f.siteId,
            roomId: f.roomId,
            userName: f.userName,
            avatar: f.avatar,
            live: false,
            subtitle: f.refreshing ? '刷新中…' : (f.state === LiveState.Replay ? '轮播中' :
              (f.state === LiveState.Unknown ? SiteStyle.label(f.siteId) : `${SiteStyle.label(f.siteId)} · 未开播`))
          })
            .width(this.cardW(this.tileCols, Space.lg))
        }, (f: FollowItem) => f.renderKey)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ bottom: Space.lg })
    }
  }

  build() {
    Refresh({ refreshing: $$this.pullRefreshing, builder: this.refreshIndicator() }) {
      List() {
        ListItem() {
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
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: this.visible.length > 0 ? Space.xl : 0 })
        }

        ForEach(this.rows, (row: FollowRow) => {
          ListItem() {
            this.followRowView(row)
          }
        }, (r: FollowRow) => r.key)
      }
      .width('100%')
      .height('100%')
      .cachedCount(2)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .contentStartOffset(AppEnv.inst.statusBarHeight + 24)
      .contentEndOffset(Layout.bottomNavInset)
      .padding({ left: Space.page, right: Space.page })
    }
    .onRefreshing(() => {
      if (this.pullEndTimer !== -1) {
        clearTimeout(this.pullEndTimer);
        this.pullEndTimer = -1;
      }
      this.pullStartedAt = Date.now();
      this.pullRefreshing = true;
      FollowStore.inst.refreshAll(true);
    })
    .refreshOffset(56)
    .pullDownRatio(0.85)
    .onAreaChange((o: Area, n: Area) => {
      this.areaW = n.width as number;
    })
  }

  @Builder
  refreshIndicator() {
    RefreshGlow({ refreshing: this.pullRefreshing })
  }
}
