import { LiveRoomItem, LiveSubCategory, SiteId } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { Feeds } from '../app/Feeds';
import { CategoryStore } from '../app/CategoryStore';
import { SubCategoryTile } from './CategoryView';
import { RoomFeed } from '../app/RoomFeed';
import { FollowItem, FollowStore } from '../app/Stores';
import { Settings } from '../app/Settings';
import { AppEnv } from '../app/AppEnv';
import { Nav } from '../app/Nav';
import { C, Layout, Motion, Radius, Space } from '../theme/Theme';
import { RoomGrid } from '../components/RoomGrid';
import { Avatar, RefreshGlow, Segmented } from '../components/Basics';
import { AmbientGlow, SectionTitle } from '../components/Decor';
import { HomeHero } from './HomeHero';
import { HomeHeroState } from './HomeHeroState';

const SITE_LABELS: string[] = ['虎牙', '斗鱼', 'B站'];

@ComponentV2
export struct HomeView {
  @Param active: boolean = false;
  @Event onSeeFollows: () => void = () => {};
  @Event onSeeCategories: () => void = () => {};
  @Local site: SiteId = Settings.inst.homeSite;
  @Local drawnSites: SiteId[] = [this.site];
  @Local alignSite: string = '';
  @Local alignY: number = -1;
  @Local alignSeq: number = 0;
  private switchSeq: number = 0;
  private mounted: boolean = false;
  private outerScroller: Scroller = new Scroller();
  private listY: number = 0;
  @Local scrollY: number = 0;
  @Local ambientCover: string = '';
  @Local contentW: number = 1100;
  @Local contentH: number = AppEnv.inst.winHeight;
  @Local favoriteCategories: LiveSubCategory[] = CategoryStore.favorites();
  @Local followSnapshot: FollowItem[] = FollowStore.inst.items;
  private syncFavorites: () => void = () => {
    this.favoriteCategories = CategoryStore.favorites();
  };
  private syncFollows: () => void = () => {
    this.followSnapshot = FollowStore.inst.items.slice();
  };

  aboutToAppear(): void {
    this.mounted = true;
    CategoryStore.subscribeFavorites(this.syncFavorites);
    FollowStore.inst.subscribe(this.syncFollows);
    this.syncFavorites();
    this.syncFollows();
    // The same caches serve the common hero and the three retained recommendation lists.
    for (const site of Sites.ids) {
      const feed = Feeds.recommendOf(site);
      if (feed.items.length === 0 && !feed.initialLoading) feed.load();
    }
    FollowStore.inst.refreshAll();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.clearSwitch();
    CategoryStore.unsubscribeFavorites(this.syncFavorites);
    FollowStore.inst.unsubscribe(this.syncFollows);
  }

  @Monitor('active')
  onActive(): void {
    if (!this.active) this.clearSwitch();
  }

  private clearSwitch(): void {
    this.switchSeq++;
    this.drawnSites = [this.site];
  }

  private finishSwitch(seq: number): void {
    if (this.mounted && this.active && seq === this.switchSeq) this.drawnSites = [this.site];
  }

  private siteOffset(site: SiteId): number {
    if (AppEnv.inst.reduceMotion || site === this.site) return 0;
    return Sites.ids.indexOf(site) < Sites.ids.indexOf(this.site) ? -28 : 28;
  }

  private ensureLoaded(): void {
    const feed = this.feed;
    if (feed.items.length === 0 && !feed.initialLoading) feed.load();
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
    if (live.length > 0) return live;
    return HomeHeroState.fallback(Sites.ids.map((site: SiteId) => Feeds.recommendOf(site).items));
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
    return this.contentW < 760;
  }

  get heroHeight(): number {
    return this.compact ? this.contentW * 9 / 16 : Math.max(260, Math.min(360, AppEnv.inst.winHeight * 0.4));
  }

  private selectSite(i: number): void {
    const id = Sites.ids[i];
    if (!this.mounted || !this.active || id === undefined || id === this.site) return;
    // The outer scroll is shared; only the bounded list below it needs alignment.
    this.alignSite = id;
    this.alignY = this.listY;
    this.alignSeq++;
    const seq = ++this.switchSeq;
    if (AppEnv.inst.reduceMotion) {
      this.site = id;
      this.drawnSites = [id];
    } else {
      if (!this.drawnSites.includes(id)) this.drawnSites = this.drawnSites.concat(id);
      // Retarget native animation from its current presentation; no delayed selection or scroll.
      this.getUIContext().animateTo({
        duration: 280, curve: Motion.snappy, onFinish: () => this.finishSwitch(seq)
      }, () => { this.site = id; });
    }
    Settings.inst.homeSite = id;
    Settings.inst.scheduleSave();
    this.ensureLoaded();
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
  liveStrip() {
    if (this.liveFollows.length > 0) {
      Column({ space: 12 }) {
        Row() {
          SectionTitle({ title: '正在直播', subtitle: `${this.liveFollows.length} 位关注的主播` })
          Blank()
          Row({ space: 2 }) {
            Text('全部').fontSize(13).fontColor(C.text2)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([C.text2])
          }
          .height(40)
          .padding({ left: 12, right: 12 })
          .onClick(() => this.onSeeFollows())
        }
        .width('100%')
        List({ space: 12 }) {
          ForEach(this.liveFollows, (f: FollowItem) => {
            ListItem() {
              Row({ space: 10 }) {
                Avatar({ src: f.avatar, dim: 40, live: true })
                Column({ space: 2 }) {
                  Text(f.userName)
                    .fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.text1)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(f.area.length > 0 ? f.area : f.title)
                    .fontSize(11).fontColor(C.text2)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .constraintSize({ maxWidth: 130 })
              }
              .padding({ left: 8, right: 16, top: 8, bottom: 8 })
              .borderRadius(Radius.pill)
              .backgroundColor(C.bgElevated)
              .borderWidth(1)
              .borderColor(C.stroke)
              .onClick(() => Nav.openLive(f.toRoomItem()))
            }
          }, (f: FollowItem) => f.key)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .height(64)
        .width('100%')
        .clip(false)
      }
      .width('100%')
      .margin({ top: 8 })
    }
  }

  @Builder
  commonCategoryStrip() {
    Column({ space: 12 }) {
      Row() {
        SectionTitle({ title: '常用分类', subtitle: this.favoriteCategories.length > 0 ? '跨平台快速进入' : '长按分类可添加' })
        Blank()
        Text(this.favoriteCategories.length > 0 ? '管理' : '去添加')
          .fontSize(13).fontColor(C.text2).height(40)
          .padding({ left: 12, right: 12 })
          .onClick(() => this.onSeeCategories())
      }
      .width('100%')
      if (this.favoriteCategories.length > 0) {
        List({ space: 6 }) {
          ForEach(this.favoriteCategories, (category: LiveSubCategory) => {
            ListItem() { SubCategoryTile({ c: category, showSite: true }) }
          }, (category: LiveSubCategory) => `${category.siteId}_${category.id}`)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .height(128)
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  header() {
    Column({ space: Space.xl }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(20).fontColor([C.accent])
          Text('搜索直播间、主播或链接')
            .fontSize(16).fontColor(C.text2).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([C.text3])
        }
        .width('100%')
        .padding({ left: 18, right: 18 })
      }
      .width('100%')
      .height(52)
      .padding(0)
      .borderRadius(Radius.pill)
      .backgroundColor(C.glassTint)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .borderWidth(0.5)
      .borderColor(C.glassStroke)
      .shadow({ radius: 16, color: '#1A000000', offsetY: 4 })
      .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.8) } })
      .accessibilityText('搜索直播间、主播或链接')
      .id('home_search')
      .onClick(() => Nav.openSearch())
      HomeHero({
        items: this.heroItems, fromFollows: this.liveFollows.length > 0,
        active: this.active && AppEnv.inst.foreground, compact: this.compact,
        heroHeight: this.heroHeight, error: this.heroError, loading: this.heroLoading,
        onRetry: () => this.retryHero(), onCover: (cover: string) => { this.ambientCover = cover; }
      })
      this.liveStrip()
      this.commonCategoryStrip()
      Row() {
        SectionTitle({ title: '为你推荐' })
        Blank()
        Segmented({
          items: SITE_LABELS, glass: true, selected: Sites.ids.indexOf(this.site),
          onSelect: (i: number) => this.selectSite(i)
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: Space.page, right: Space.page, top: AppEnv.inst.statusBarHeight + 20, bottom: Space.xl })
  }

  @Builder
  recommendations() {
    Stack({ alignContent: Alignment.Top }) {
      ForEach(Sites.ids, (site: SiteId) => {
        RoomGrid({
          feed: Feeds.recommendOf(site), scope: `home_${site}`,
          active: this.active && site === this.site, bottomInset: Layout.bottomNavInset,
          nested: true, externalRefresh: true,
          alignY: this.alignY, alignSeq: site === this.alignSite ? this.alignSeq : 0,
          onScrollY: (y: number) => this.onListScroll(site, y)
        })
          .width('100%')
          .height('100%')
          .visibility(this.drawnSites.includes(site) ? Visibility.Visible : Visibility.Hidden)
          .opacity(site === this.site ? 1 : 0)
          .translate({ x: this.siteOffset(site) })
          .enabled(site === this.site)
          .hitTestBehavior(site === this.site ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(site === this.site ? 'auto' : 'no-hide-descendants')
      }, (site: SiteId) => site)
    }
    .width('100%')
    .height(Math.max(1, this.contentH))
    .id('home_recommendations')
    .clip(true)
  }

  @Builder
  refreshIndicator() {
    RefreshGlow({ refreshing: this.feed.refreshing })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      AmbientGlow({
        src: this.ambientCover, strength: Math.max(0, 1 - this.scrollY / 420),
        glowHeight: this.heroHeight + AppEnv.inst.statusBarHeight + 200
      })
      Refresh({ refreshing: this.feed.refreshing, builder: this.refreshIndicator() }) {
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
      .refreshOffset(64)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.contentW = (area.width as number) - Space.page * 2;
      this.contentH = area.height as number;
    })
  }
}
