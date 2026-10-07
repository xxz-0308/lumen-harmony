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
import { C, formatOnline, Layout, Motion, Radius, Space } from '../theme/Theme';
import { RoomGrid } from '../components/RoomGrid';
import { heroIdFor } from '../components/RoomCard';
import { Avatar, LiveDot, NetImage, Segmented, Shimmer, SiteBadge, StateView } from '../components/Basics';
import { AmbientGlow, PillIndicator, SectionTitle } from '../components/Decor';

import { HeroSource } from '../room/HeroSources';

const SITE_LABELS: string[] = ['虎牙', '斗鱼', 'B站'];

/** One source per rendered slide; hidden platform copies never register the same hero id. */
@ComponentV2
struct HomeHeroSource {
  @Param item: LiveRoomItem = new LiveRoomItem();
  @Param eligible: boolean = false;
  @BuilderParam content: () => void;
  private source: HeroSource = new HeroSource();

  aboutToAppear(): void { this.syncSource(); }
  aboutToDisappear(): void { this.source.unmount(); }

  @Monitor('eligible', 'item')
  syncSource(): void {
    if (this.eligible) this.source.mount(heroIdFor('hero', this.item));
    else this.source.unmount();
  }

  build() {
    Stack() { this.content() }
      .width('100%')
      .height('100%')
      .onVisibleAreaChange([0, 1], (visible: boolean, ratio: number) => {
        this.source.setVisible(this.eligible && visible && ratio >= 1);
      })
      .onAreaChange((o: Area, n: Area) => {
        this.source.setBounds(`${n.globalPosition.x}_${n.globalPosition.y}_${n.width}_${n.height}`);
      })
      .onClick(() => {
        this.source.capture();
        Nav.openLive(this.item, this.eligible ? heroIdFor('hero', this.item) : '');
      })
  }
}

@ComponentV2
export struct HomeView {
  @Param active: boolean = false;
  @Event onSeeFollows: () => void = () => {
  };
  @Event onSeeCategories: () => void = () => {
  };
  @Local site: SiteId = Settings.inst.homeSite;
  /** The grid sliding out after a switch; it stays drawn until its exit animation ends. */
  @Local leavingSite: string = '';
  @Local alignSite: string = '';
  @Local alignY: number = -1;
  @Local alignSeq: number = 0;
  private leaveTimer: number = -1;
  @Local heroIndex: number = 0;
  /** Auto-rotation pauses while the user is touching the hero, so a tap can't land on a swap. */
  @Local heroTouched: boolean = false;
  @Local touchedItems: LiveRoomItem[] = [];
  private releaseHeroTimer: number = -1;
  @Local heroOpacity: number[] = [];
  @Local heroShift: number[] = [];
  @Local scrollY: number = 0;
  private lastOffsets: Map<string, number> = new Map<string, number>();
  private firstVisit: Set<string> = new Set<string>();
  @Local contentW: number = 1100;
  @Local favoriteCategories: LiveSubCategory[] = CategoryStore.favorites();
  @Local followSnapshot: FollowItem[] = FollowStore.inst.items;
  private syncFavorites: () => void = () => {
    this.favoriteCategories = CategoryStore.favorites();
  };
  private syncFollows: () => void = () => {
    this.followSnapshot = FollowStore.inst.items.slice();
  };

  aboutToAppear(): void {
    CategoryStore.subscribeFavorites(this.syncFavorites);
    FollowStore.inst.subscribe(this.syncFollows);
    this.syncFavorites();
    this.syncFollows();
    this.firstVisit.add(this.site);
    this.ensureLoaded();
    // Preload the other recommendations without starting any video; tab switches stay populated.
    for (const site of Sites.ids) {
      const feed = Feeds.recommendOf(site);
      if (feed.items.length === 0 && !feed.initialLoading) {
        feed.load();
      }
    }
    FollowStore.inst.refreshAll();
  }

  aboutToDisappear(): void {
    if (this.releaseHeroTimer >= 0) {
      clearTimeout(this.releaseHeroTimer);
      this.releaseHeroTimer = -1;
    }
    CategoryStore.unsubscribeFavorites(this.syncFavorites);
    FollowStore.inst.unsubscribe(this.syncFollows);
  }

  @Monitor('active')
  onActive(): void {
    if (!this.active) {
      if (this.releaseHeroTimer >= 0) clearTimeout(this.releaseHeroTimer);
      this.releaseHeroTimer = -1;
      this.heroTouched = false;
      this.touchedItems = [];
    }
  }

  private ensureLoaded(): void {
    const f = Feeds.recommendOf(this.site);
    if (f.items.length === 0 && !f.initialLoading) {
      f.load();
    }
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
  get commonCategories(): LiveSubCategory[] {
    return this.favoriteCategories;
  }

  /** Followed anchors that are live take the stage; otherwise the top recommendations. */
  @Computed
  get heroItems(): LiveRoomItem[] {
    if (this.heroTouched && this.touchedItems.length > 0) {
      return this.touchedItems;
    }
    const live = this.liveFollows.slice(0, 6).map((f: FollowItem) => f.toRoomItem());
    if (live.length > 0) {
      return live;
    }
    return this.feed.items.slice(0, 5);
  }

  @Computed
  get heroFromFollows(): boolean {
    return this.liveFollows.length > 0;
  }

  @Monitor('heroFromFollows')
  onHeroSource(): void {
    // The source can flip between follows and recommendations; start from the top again.
    if (!this.heroTouched) {
      this.heroIndex = 0;
    }
  }

  get compact(): boolean {
    return this.contentW < 760;
  }

  get heroHeight(): number {
    const h = AppEnv.inst.winHeight;
    return this.compact ? this.contentW * 9 / 16 : Math.max(260, Math.min(360, h * 0.4));
  }

  private selectSite(i: number): void {
    const id = Sites.ids[i];
    if (id === this.site) {
      return;
    }
    const current = this.site;
    // Keep the viewer exactly where they are: the next platform's grid takes over the current
    // scroll offset (clamped by the list) before it slides in.
    const offset = this.lastOffsets.get(current) ?? 0;
    this.lastOffsets.set(id, offset);
    this.firstVisit.add(id);
    this.alignSite = id;
    this.alignY = offset;
    this.alignSeq++;
    this.leavingSite = current;
    if (this.leaveTimer >= 0) {
      clearTimeout(this.leaveTimer);
    }
    this.leaveTimer = setTimeout(() => {
      this.leaveTimer = -1;
      this.leavingSite = '';
    }, 320);
    this.site = id;
    Settings.inst.homeSite = id;
    Settings.inst.scheduleSave();
    this.heroIndex = 0;
    this.ensureLoaded();
  }

  private heroCover(item: LiveRoomItem): string {
    if (item.siteId === 'huya') {
      // Huya's w1280_h720 OSS style returns 404; the unstyled screenshot is the full-size source.
      return item.cover.replace('?x-oss-process=style/w338_h190&', '');
    }
    if (item.siteId === 'bilibili') {
      return item.cover.replace('@400w.jpg', '@1280w.jpg');
    }
    return item.cover;
  }

  @Builder
  heroSlide(item: LiveRoomItem, index: number, hostSite: SiteId) {
    HomeHeroSource({ item: item, eligible: hostSite === this.site && !AppEnv.inst.reduceMotion }) {
      this.heroSlideContent(item, index, hostSite)
    }
  }

  @Builder
  heroSlideContent(item: LiveRoomItem, index: number, hostSite: SiteId) {
    Row({ space: 32 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        NetImage({ src: this.heroCover(item) })
        if (this.compact) {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({ angle: 180, colors: [['#00000000', 0.35], ['#CC000000', 1]] })
          Column({ space: 6 }) {
            Text(item.userName)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(C.onMedia)
            Text(item.title)
              .fontSize(14)
              .fontColor(C.onMedia2)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .position({ left: 18, bottom: 16 })
          .padding({ right: 18 })
        }
        Row({ space: 6 }) {
          LiveDot({ dim: 6, color: '#FFFFFF' })
          Text(this.heroFromFollows ? '关注 · 直播中' : 'LIVE')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .letterSpacing(this.heroFromFollows ? 0 : 1)
        }
        .padding({ left: 10, right: 12, top: 5, bottom: 5 })
        .borderRadius(Radius.pill)
        .backgroundColor(C.live)
        .margin(14)
      }
      .height('100%')
      .aspectRatio(16 / 9)
      .constraintSize({ maxWidth: this.compact ? '100%' : '60%' })
      .borderRadius(Radius.xl)
      .clip(true)
      .shadow({ radius: 40, color: '#4D000000', offsetY: 16 })
      .geometryTransition(hostSite === this.site && !AppEnv.inst.reduceMotion ? heroIdFor('hero', item) : '', { follow: true })

      if (!this.compact) {
        Column({ space: 14 }) {
          Row({ space: 8 }) {
            SiteBadge({ siteId: item.siteId, onMedia: false })
            if (item.area.length > 0) {
              Text(item.area)
                .fontSize(12)
                .fontColor(C.text2)
            }
          }
          Row({ space: 14 }) {
            Avatar({ src: item.avatar, dim: 52, live: true })
            Column({ space: 4 }) {
              Text(item.userName)
                .fontSize(26)
                .fontWeight(FontWeight.Bolder)
                .fontColor(C.text1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.flame_fill'))
                  .fontSize(13)
                  .fontColor([C.accent])
                Text(`${formatOnline(item.online)} 人气`)
                  .fontSize(13)
                  .fontColor(C.text2)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          Text(item.title)
            .fontSize(17)
            .lineHeight(25)
            .fontColor(C.text2)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(16)
              .fontColor([Color.White])
            Text('进入直播间')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .height(44)
          .padding({ left: 20, right: 24 })
          .borderRadius(Radius.pill)
          .linearGradient({ angle: 100, colors: [[C.accentHighlight, 0], [C.accent, 1]] })
          .shadow({ radius: 18, color: C.accentGlow, offsetY: 6 })
          .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
        .translate({ x: AppEnv.inst.reduceMotion ? 0 : (this.heroShift[index] ?? 0) * 60 })
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.heroOpacity[index] ?? 1)
  }

  @Builder
  hero(hostSite: SiteId) {
    if (this.heroItems.length === 0 && this.feed.error.length > 0) {
      // Never leave the hero shimmering forever when the feed failed.
      StateView({
        icon: $r('sys.symbol.exclamationmark_message'),
        title: '推荐加载失败',
        subtitle: this.feed.error,
        actionText: '重试',
        onAction: () => {
          this.feed.load();
        }
      })
        .width('100%')
        .height(this.heroHeight)
    } else if (this.heroItems.length === 0) {
      Row({ space: 32 }) {
        Shimmer({ radius: Radius.xl })
          .height('100%')
          .aspectRatio(16 / 9)
        if (!this.compact) {
          Column({ space: 14 }) {
            Shimmer({ radius: 6 })
              .width('40%')
              .height(22)
            Shimmer({ radius: 6 })
              .width('70%')
              .height(30)
            Shimmer({ radius: 6 })
              .width('90%')
              .height(16)
            Shimmer({ radius: 22 })
              .width(150)
              .height(44)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .height(this.heroHeight)
    } else {
      Column({ space: 16 }) {
        Swiper() {
          ForEach(this.heroItems, (item: LiveRoomItem, i: number) => {
            this.heroSlide(item, i, hostSite)
          }, (item: LiveRoomItem) => `${item.siteId}_${item.roomId}`)
        }
        .width('100%')
        .height(this.heroHeight)
        .indicator(false)
        .loop(this.heroItems.length > 1)
        .autoPlay(!AppEnv.inst.reduceMotion && this.active && hostSite === this.site && Settings.inst.heroAutoPlay && this.heroItems.length > 1 && !this.heroTouched)
        .interval(6500)
        .curve(Motion.smooth)
        .clip(false)
        .index(this.heroIndex)
        .onChange((i: number) => {
          this.heroIndex = i;
        })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            if (this.releaseHeroTimer >= 0) {
              clearTimeout(this.releaseHeroTimer);
            }
            this.touchedItems = this.heroItems.slice();
            this.heroTouched = true;
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.releaseHeroTimer = setTimeout(() => {
              this.releaseHeroTimer = -1;
              this.heroTouched = false;
              this.touchedItems = [];
              if (this.heroIndex >= this.heroItems.length) {
                this.heroIndex = 0;
              }
            }, 200);
          }
        })
        .customContentTransition({
          timeout: 1000,
          transition: (proxy: SwiperContentTransitionProxy) => {
            const p = Math.max(-1, Math.min(1, proxy.position));
            this.heroOpacity[proxy.index] = 1 - Math.abs(p) * 0.7;
            this.heroShift[proxy.index] = p;
          }
        })
        if (this.heroItems.length > 1) {
          PillIndicator({ count: this.heroItems.length, index: this.heroIndex })
        }
      }
    }
  }

  @Builder
  liveStrip() {
    if (this.liveFollows.length > 0) {
      Column({ space: 12 }) {
        Row() {
          SectionTitle({ title: '正在直播', subtitle: `${this.liveFollows.length} 位关注的主播` })
          Blank()
          Row({ space: 2 }) {
            Text('全部')
              .fontSize(13)
              .fontColor(C.text2)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([C.text2])
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
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(C.text1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(f.area.length > 0 ? f.area : f.title)
                    .fontSize(11)
                    .fontColor(C.text2)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
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
        SectionTitle({ title: '常用分类', subtitle: this.commonCategories.length > 0 ? '跨平台快速进入' : '长按分类可添加' })
        Blank()
        Text(this.commonCategories.length > 0 ? '管理' : '去添加')
          .fontSize(13)
          .fontColor(C.text2)
          .height(40)
          .padding({ left: 12, right: 12 })
          .onClick(() => this.onSeeCategories())
      }
      .width('100%')
      if (this.commonCategories.length > 0) {
        List({ space: 6 }) {
          ForEach(this.commonCategories, (category: LiveSubCategory) => {
            ListItem() {
              SubCategoryTile({ c: category, showSite: true })
            }
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
  header(hostSite: SiteId) {
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
      // Glass over the ambient glow, like the other floating controls.
      .backgroundColor(C.glassTint)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .borderWidth(0.5)
      .borderColor(C.glassStroke)
      .shadow({ radius: 16, color: '#1A000000', offsetY: 4 })
      .stateStyles({
        normal: { .opacity(1) },
        pressed: { .opacity(0.8) }
      })
      .accessibilityText('搜索直播间、主播或链接')
      .id('home_search')
      .onClick(() => Nav.openSearch())
      this.hero(hostSite)
      this.liveStrip()
      this.commonCategoryStrip()
      Row() {
        SectionTitle({ title: '为你推荐' })
        Blank()
        Segmented({
          items: SITE_LABELS,
          glass: true,
          selected: Sites.ids.indexOf(this.site),
          onSelect: (i: number) => this.selectSite(i)
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      AmbientGlow({
        src: this.heroItems.length > 0 ? this.heroItems[Math.min(this.heroIndex, this.heroItems.length - 1)].cover : '',
        strength: Math.max(0, 1 - this.scrollY / 420),
        glowHeight: this.heroHeight + AppEnv.inst.statusBarHeight + 200
      })
      // Keep each platform's ListScroller and card handlers mounted. Only the active grid can
      // interact or attach its hero geometry; changing the feed prop on one grid recycled cards.
      ForEach(Sites.ids, (site: SiteId) => {
        Stack() {
          RoomGrid({
            feed: Feeds.recommendOf(site),
            scope: `home_${site}`,
            active: this.active && site === this.site,
            bottomInset: Layout.bottomNavInset,
            startOffset: this.lastOffsets.get(site) ?? 0,
            alignY: this.alignY,
            alignSeq: site === this.alignSite ? this.alignSeq : 0,
            topPadding: AppEnv.inst.statusBarHeight + 20,
            onScrollY: (y: number) => {
              if (site !== this.site) {
                return;
              }
              this.lastOffsets.set(site, Math.max(0, y));
              const q = Math.round(y / 24) * 24;
              if (q !== this.scrollY) {
                this.scrollY = q;
              }
            }
          }) {
            this.header(site)
          }
        }
        .width('100%')
        .height('100%')
        // Inactive grids stay laid out (Hidden) so they can be aligned before they appear; the
        // incoming one slides in from its side of the switcher, the outgoing one slides away.
        .visibility(site === this.site || site === this.leavingSite ? Visibility.Visible : Visibility.Hidden)
        .opacity(site === this.site ? 1 : 0)
        .translate({ x: site === this.site ? 0 :
          (Sites.ids.indexOf(site) < Sites.ids.indexOf(this.site) ? -56 : 56) })
        .animation({ duration: AppEnv.inst.reduceMotion ? 0 : 280, curve: Motion.smooth })
        .enabled(site === this.site)
      }, (site: SiteId) => site)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((o: Area, n: Area) => {
      this.contentW = (n.width as number) - Space.page * 2;
    })
  }
}
