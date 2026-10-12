import { LiveRoomItem, LiveSubCategory, SiteId } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { Feeds } from '../app/Feeds';
import { CategoryStore } from '../app/CategoryStore';
import { RoomFeed } from '../app/RoomFeed';
import { FollowItem, FollowStore } from '../app/Stores';
import { Settings } from '../app/Settings';
import { AppEnv } from '../app/AppEnv';
import { Nav } from '../app/Nav';
import { NavigationActivity } from '../app/NavigationActivity';
import { C, formatOnline, Layout, Motion, Radius, SiteStyle, Space } from '../theme/Theme';
import { RoomGrid } from '../components/RoomGrid';
import { Avatar, NetImage, RefreshGlow, Segmented } from '../components/Basics';
import { AmbientGlow, SectionTitle } from '../components/Decor';
import { HomeHero } from './HomeHero';
import { HomeHeroState } from './HomeHeroState';
import { SiteSwitch } from './SiteSwitch';

@ComponentV2
export struct HomeView {
  @Param active: boolean = false;
  @Event onSeeFollows: () => void = () => {};
  @Event onSeeCategories: () => void = () => {};
  @Local navActivity: NavigationActivity = NavigationActivity.inst;
  @Local env: AppEnv = AppEnv.inst;
  @Local site: SiteId = Settings.inst.homeSite;
  @Local drawnSites: SiteId[] = [this.site];
  @Local visitedSites: SiteId[] = [this.site];
  @Local alignSite: string = '';
  @Local alignY: number = -1;
  @Local alignSeq: number = 0;
  private switchSeq: number = 0;
  private mounted: boolean = false;
  private outerScroller: Scroller = new Scroller();
  private sideScroller: Scroller = new Scroller();
  private listY: number = 0;
  @Local scrollY: number = 0;
  @Local ambientCover: string = '';
  @Local totalW: number = 1400;
  @Local contentH: number = AppEnv.inst.winHeight;
  @Local favoriteCategories: LiveSubCategory[] = CategoryStore.favorites();
  @Local followSnapshot: FollowItem[] = [];
  @Local heroVisible: boolean = true;
  private followRevision: number = -1;
  private syncFavorites: () => void = () => {
    if (this.mounted && this.running) this.favoriteCategories = CategoryStore.favorites();
  };
  private syncFollows: () => void = () => {
    if (!this.mounted || !this.running) return;
    const revision = FollowStore.inst.contentRevision;
    if (revision !== this.followRevision) {
      this.followSnapshot = FollowStore.inst.items.map((f: FollowItem) => f.snapshot());
      this.followRevision = revision;
    }
  };

  aboutToAppear(): void {
    this.mounted = true;
    CategoryStore.subscribeFavorites(this.syncFavorites);
    FollowStore.inst.subscribe(this.syncFollows);
    this.syncFavorites();
    this.syncFollows();
    for (const site of Sites.ids) {
      const feed = Feeds.recommendOf(site);
      if (feed.items.length === 0 && !feed.initialLoading) feed.load();
    }
    CategoryStore.ensure(this.site);
    FollowStore.inst.refreshAll();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.clearSwitch();
    CategoryStore.unsubscribeFavorites(this.syncFavorites);
    FollowStore.inst.unsubscribe(this.syncFollows);
  }

  get running(): boolean { return this.active && this.navActivity.rootActive && this.env.foreground; }

  @Monitor('active', 'navActivity.rootActive', 'env.foreground')
  onActive(): void {
    if (!this.running) this.clearSwitch();
    else {
      this.syncFavorites();
      this.syncFollows();
    }
  }

  get heroActive(): boolean {
    return this.running && this.heroVisible && AppEnv.inst.foreground;
  }

  private clearSwitch(): void {
    this.switchSeq++;
    this.drawnSites = [this.site];
  }

  private finishSwitch(seq: number): void {
    if (this.mounted && this.running && seq === this.switchSeq) this.drawnSites = [this.site];
  }

  private siteOffset(site: SiteId): number {
    return SiteSwitch.offset(Sites.ids, site, this.site, AppEnv.inst.reduceMotion);
  }

  private ensureLoaded(): void {
    const feed = this.feed;
    if (feed.items.length === 0 && !feed.initialLoading) feed.load();
    CategoryStore.ensure(this.site);
  }

  @Computed
  get feed(): RoomFeed {
    return Feeds.recommendOf(this.site);
  }

  @Computed
  get liveFollows(): FollowItem[] {
    return this.followSnapshot.filter((f: FollowItem) => f.isLive)
      .sort((a: FollowItem, b: FollowItem) => b.online - a.online);
  }

  @Computed
  get heroItems(): LiveRoomItem[] {
    const live = this.liveFollows.slice(0, 6).map((f: FollowItem) => f.toRoomItem());
    if (live.length >= 4) return live;
    const fallback = HomeHeroState.fallback(Sites.ids.map((site: SiteId) => Feeds.recommendOf(site).items));
    const seen = new Set<string>(live.map((it: LiveRoomItem) => `${it.siteId}_${it.roomId}`));
    const merged: LiveRoomItem[] = [...live];
    for (const item of fallback) {
      const k = `${item.siteId}_${item.roomId}`;
      if (!seen.has(k)) {
        seen.add(k);
        merged.push(item);
        if (merged.length >= 6) break;
      }
    }
    return merged;
  }

  @Computed
  get quickCategories(): LiveSubCategory[] {
    const out: LiveSubCategory[] = [];
    const seen = new Set<string>();
    const seenNames = new Set<string>();
    for (const c of this.favoriteCategories) {
      const k = `${c.siteId}_${c.id}`;
      if (!seen.has(k) && !seenNames.has(c.name)) {
        seen.add(k);
        seenNames.add(c.name);
        out.push(c);
        if (out.length >= 6) return out;
      }
    }
    const groups = CategoryStore.of(this.site).groups;
    for (const g of groups) {
      for (const c of g.children) {
        const k = `${c.siteId}_${c.id}`;
        if (!seen.has(k) && !seenNames.has(c.name)) {
          seen.add(k);
          seenNames.add(c.name);
          out.push(c);
          if (out.length >= 6) return out;
        }
      }
    }
    return out;
  }

  @Computed
  get heroLoading(): boolean {
    return Sites.ids.some((site: SiteId) => Feeds.recommendOf(site).initialLoading);
  }

  @Computed
  get heroError(): string {
    if (this.heroItems.length > 0 || this.heroLoading) return '';
    for (const site of Sites.ids) {
      const error = Feeds.recommendOf(site).error;
      if (error.length > 0) return error;
    }
    return '';
  }

  private retryHero(): void {
    for (const site of Sites.ids) {
      const feed = Feeds.recommendOf(site);
      if (feed.items.length === 0 && !feed.initialLoading) feed.load();
    }
  }

  get compact(): boolean {
    return this.totalW < 920;
  }

  get narrowTopBar(): boolean {
    return this.totalW < 560;
  }

  get heroHeight(): number {
    return this.compact ? (this.totalW - Space.page * 2) * 9 / 16 : 244;
  }

  private selectSite(i: number): void {
    const id = Sites.ids[i];
    if (!this.mounted || !this.running || id === undefined || id === this.site) return;
    this.visitedSites = SiteSwitch.include(this.visitedSites, id);
    this.alignSite = id;
    this.alignY = this.listY;
    this.alignSeq++;
    const seq = ++this.switchSeq;
    if (AppEnv.inst.reduceMotion) {
      this.site = id;
      this.drawnSites = [id];
    } else {
      this.drawnSites = SiteSwitch.include(this.drawnSites, id);
      this.getUIContext().animateTo({
        duration: SiteSwitch.DURATION_MS, curve: Motion.snappy, onFinish: () => this.finishSwitch(seq)
      }, () => { this.site = id; });
    }
    Settings.inst.homeSite = id;
    Settings.inst.scheduleSave();
    this.ensureLoaded();
  }

  private onHorizontalSwipe(e: GestureEvent): void {
    const next = SiteSwitch.swipedIndex(Sites.ids, this.site, e.offsetX, e.offsetY);
    if (next >= 0) {
      this.selectSite(next);
    }
  }

  private onListScroll(site: SiteId, y: number): void {
    if (!this.mounted || site !== this.site) return;
    this.listY = Math.max(0, y);
    this.updateGlow();
  }

  private updateGlow(): void {
    const y = Math.max(0, this.outerScroller.currentOffset().yOffset) + this.listY;
    const q = Math.round(y / 24) * 24;
    if (q !== this.scrollY) this.scrollY = q;
  }

  @Builder
  topBar() {
    Row({ space: this.narrowTopBar ? 10 : 16 }) {
      Text('探索')
        .fontSize(this.narrowTopBar ? 26 : 32)
        .fontWeight(FontWeight.Bolder)
        .fontColor(C.text1)
        .letterSpacing(-0.5)

      Blank()

      Segmented({
        items: SiteSwitch.LABELS, glass: true, selected: Sites.ids.indexOf(this.site),
        barHeight: 42, segmentWidth: this.narrowTopBar ? 50 : 62,
        onSelect: (i: number) => this.selectSite(i)
      })

      Button({ type: ButtonType.Normal }) {
        if (this.narrowTopBar) {
          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(17).fontColor([C.text1])
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([C.text2])
            Text('搜索直播间或主播')
              .fontSize(13).fontColor(C.text2).layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
      }
      .width(this.narrowTopBar ? 42 : (this.compact ? 168 : 208))
      .height(42)
      .padding(0)
      .borderRadius(Radius.pill)
      .backgroundColor(C.surface2)
      .accessibilityText('搜索直播间、主播或链接')
      .id('home_search')
      .onClick(() => Nav.openSearch())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * Concept B Right Dock Card 1: "正在直播的关注"
   * 2-column mini live room cards with 16:9 covers, red LIVE pill, viewer count, and streamer info.
   */
  @Builder
  liveFollowCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('正在直播的关注')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text1)
        if (this.liveFollows.length > 0) {
          Text(`${this.liveFollows.length}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(C.live)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(Radius.pill)
            .backgroundColor('#1FFF3B30')
        }
        Blank()
        Row({ space: 2 }) {
          Text('全部').fontSize(12).fontColor(C.text2)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([C.text3])
        }
        .onClick(() => this.onSeeFollows())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.liveFollows.length > 0) {
        GridRow({ columns: 2, gutter: { x: 12, y: 14 } }) {
          ForEach(this.liveFollows.slice(0, 4), (f: FollowItem) => {
            GridCol() {
              Column({ space: 8 }) {
                Stack({ alignContent: Alignment.TopStart }) {
                  NetImage({
                    src: f.cover.length > 0 ? f.cover : f.avatar,
                    radius: 10,
                    decodeW: 240,
                    decodeH: 135
                  })
                    .width('100%')
                    .aspectRatio(16 / 9)

                  Column()
                    .width('100%')
                    .aspectRatio(16 / 9)
                    .borderRadius(10)
                    .linearGradient({ angle: 180, colors: [['#00000000', 0.45], ['#99000000', 1]] })

                  Text('LIVE')
                    .fontSize(9)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .backgroundColor(C.live)
                    .margin(6)

                  Text(formatOnline(f.online))
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#F2FFFFFF')
                    .position({ right: 6, bottom: 5 })
                }
                .width('100%')
                .aspectRatio(16 / 9)
                .borderRadius(10)
                .clip(true)

                Row({ space: 7 }) {
                  Avatar({ src: f.avatar, dim: 26, live: false })
                  Column({ space: 1 }) {
                    Text(f.userName)
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(C.text1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(f.title.length > 0 ? f.title : SiteStyle.label(f.siteId))
                      .fontSize(10)
                      .fontColor(C.text3)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
              }
              .width('100%')
              .onClick(() => Nav.openLive(f.toRoomItem()))
            }
          }, (f: FollowItem) => f.key)
        }
        .width('100%')
      } else {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
            .fontSize(20)
            .fontColor([C.text2])
          Column({ space: 3 }) {
            Text('暂时没有关注的主播在直播')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(C.text1)
            Text('去关注列表查看主播状态')
              .fontSize(11)
              .fontColor(C.text3)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .onClick(() => this.onSeeFollows())
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(Radius.xl)
    .backgroundColor(C.bgElevated)
    .shadow({ radius: 20, color: C.shadow, offsetY: 6 })
  }

  /**
   * Concept B Right Dock Card 2: "常用分类"
   * 3x2 grid of category pedestals inside the right dock card.
   */
  @Builder
  quickCategoryCard() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Text('常用分类')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.text1)
        Blank()
        Row({ space: 2 }) {
          Text(this.favoriteCategories.length > 0 ? '管理' : '全部').fontSize(12).fontColor(C.text2)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([C.text3])
        }
        .onClick(() => this.onSeeCategories())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.quickCategories.length > 0) {
        GridRow({ columns: 3, gutter: { x: 10, y: 10 } }) {
          ForEach(this.quickCategories, (cat: LiveSubCategory) => {
            GridCol() {
              Column({ space: 8 }) {
                NetImage({
                  src: cat.pic,
                  radius: 10,
                  fit: ImageFit.Cover,
                  placeholder: C.surface3,
                  decodeW: 80,
                  decodeH: 80
                })
                  .width(40)
                  .height(40)
                Text(cat.name)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(C.text1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .padding({ left: 6, right: 6, top: 12, bottom: 10 })
              .borderRadius(14)
              .backgroundColor(C.surface2)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => Nav.openCategory(cat))
            }
          }, (cat: LiveSubCategory) => `qcat_${cat.siteId}_${cat.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(Radius.xl)
    .backgroundColor(C.bgElevated)
    .shadow({ radius: 20, color: C.shadow, offsetY: 6 })
  }

  /** Concept B Right Sticky Dock ("我的动态") */
  @Builder
  rightDock() {
    Scroll(this.sideScroller) {
      Column({ space: 18 }) {
        Row() {
          Text('我的动态')
            .fontSize(26)
            .fontWeight(FontWeight.Bolder)
            .fontColor(C.text1)
            .letterSpacing(-0.3)
          Blank()
        }
        .width('100%')
        .height(42)
        .alignItems(VerticalAlign.Center)

        this.liveFollowCard()
        this.quickCategoryCard()
      }
      .width('100%')
      .padding({
        left: 4,
        right: Space.page,
        top: AppEnv.inst.statusBarHeight + 16,
        bottom: Layout.bottomNavInset
      })
    }
    .width(344)
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  header() {
    Column({ space: 20 }) {
      this.topBar()

      HomeHero({
        items: this.heroItems, fromFollows: this.liveFollows.length >= 4,
        active: this.heroActive, compact: this.compact,
        heroHeight: this.heroHeight, error: this.heroError, loading: this.heroLoading,
        onRetry: () => this.retryHero(), onCover: (cover: string) => { this.ambientCover = cover; }
      })
        .onVisibleAreaChange([0], (visible: boolean) => { this.heroVisible = visible; })

      if (this.compact) {
        this.liveFollowCard()
        this.quickCategoryCard()
      }

      Row() {
        SectionTitle({ title: '为你推荐', subtitle: `${SiteStyle.label(this.site)}热门直播` })
        Blank()
      }
      .width('100%')
      .margin({ top: 2 })
      .priorityGesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 16 })
          .onActionEnd((e: GestureEvent) => this.onHorizontalSwipe(e))
      )
    }
    .width('100%')
    .padding({
      left: Space.page,
      right: this.compact ? Space.page : 20,
      top: AppEnv.inst.statusBarHeight + 16,
      bottom: 16
    })
  }

  @Builder
  recommendations() {
    Stack({ alignContent: Alignment.Top }) {
      ForEach(Sites.ids, (site: SiteId) => {
        if (this.visitedSites.includes(site)) {
          RoomGrid({
            feed: Feeds.recommendOf(site), scope: `home_${site}`,
            active: this.running && site === this.site, bottomInset: Layout.bottomNavInset,
            nested: true, externalRefresh: true, featuredLead: false,
            minCardWidth: 248,
            rightInset: this.compact ? Space.page : 20,
            alignY: this.alignY, alignSeq: site === this.alignSite ? this.alignSeq : 0,
            onScrollY: (y: number) => this.onListScroll(site, y)
          })
            .width('100%')
            .height('100%')
            .visibility(this.drawnSites.includes(site) ? Visibility.Visible : Visibility.None)
            .opacity(site === this.site ? 1 : 0)
            .translate({ x: this.siteOffset(site) })
            .enabled(site === this.site)
            .hitTestBehavior(site === this.site ? HitTestMode.Default : HitTestMode.None)
            .accessibilityLevel(site === this.site ? 'auto' : 'no-hide-descendants')
        }
      }, (site: SiteId) => site)
    }
    .width('100%')
    .height(Math.max(1, this.contentH))
    .id('home_recommendations')
    .clip(true)
    .priorityGesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 16 })
        .onActionEnd((e: GestureEvent) => this.onHorizontalSwipe(e))
    )
  }

  @Builder
  refreshIndicator() {
    RefreshGlow({ refreshing: this.feed.refreshing })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      AmbientGlow({
        src: this.ambientCover, active: this.running, strength: Math.max(0, 1 - this.scrollY / 420),
        glowHeight: this.heroHeight + AppEnv.inst.statusBarHeight + 240
      })
      Row() {
        Refresh({ refreshing: $$this.feed.refreshing, builder: this.refreshIndicator() }) {
          Scroll(this.outerScroller) {
            Column() {
              this.header()
              this.recommendations()
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onDidScroll(() => this.updateGlow())
        }
        .onRefreshing(() => this.feed.load(true))
        .refreshOffset(56)
        .pullDownRatio(0.85)
        .layoutWeight(1)
        .height('100%')

        if (!this.compact) {
          this.rightDock()
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.totalW = area.width as number;
      this.contentH = area.height as number;
    })
  }
}
