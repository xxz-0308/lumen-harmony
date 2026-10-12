import { promptAction } from '@kit.ArkUI';
import { LiveSubCategory, SiteId } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { CategoryStore, SiteCategories } from '../app/CategoryStore';
import { Settings } from '../app/Settings';
import { AppEnv } from '../app/AppEnv';
import { Nav } from '../app/Nav';
import { C, Layout, Motion, Radius, SiteStyle, Space } from '../theme/Theme';
import { NetImage, Segmented, Shimmer, StateView } from '../components/Basics';
import { PageTitle } from '../components/Decor';
import { SiteSwitch } from './SiteSwitch';

const FAV_KEY: string = '__fav__';

class CategoryRow {
  key: string = '';
  sectionKey: string = '';
  isHeader: boolean = false;
  headerTitle: string = '';
  headerCount: number = 0;
  featured: boolean = false;
  showSite: boolean = false;
  items: LiveSubCategory[] = [];
}

class Section {
  key: string = '';
  title: string = '';
  count: number = 0;
  startRowIndex: number = 0;
  rows: CategoryRow[] = [];
}

/**
 * Tonal Squircle Pedestal Tile:
 * Places each 58x58 game icon inside a 76x76 soft-elevated tonal squircle (#FFFFFF in light / #141418 in dark,
 * zero 1px border) so white-background game icons never disappear into the #F5F5F7 page canvas.
 */
@ComponentV2
export struct SubCategoryTile {
  @Param c: LiveSubCategory = new LiveSubCategory();
  @Param showSite: boolean = false;
  @Local pressed: boolean = false;
  @Local favorite: boolean = false;
  private syncFavorite: () => void = () => {
    this.favorite = CategoryStore.isFavorite(this.c);
  };

  aboutToAppear(): void {
    CategoryStore.subscribeFavorites(this.syncFavorite);
    this.syncFavorite();
  }

  aboutToDisappear(): void {
    CategoryStore.unsubscribeFavorites(this.syncFavorite);
  }

  @Monitor('c')
  onCategory(): void {
    this.syncFavorite();
  }

  build() {
    Column({ space: 9 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Stack() {
          NetImage({
            src: this.c.pic,
            radius: 14,
            fit: ImageFit.Cover,
            placeholder: C.surface2,
            decodeW: 80,
            decodeH: 80
          })
            .width(58)
            .height(58)
        }
        .width(76)
        .height(76)
        .borderRadius(20)
        .backgroundColor(C.bgElevated)
        .shadow({ radius: 16, color: C.shadow, offsetY: 6 })

        if (this.favorite) {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(11)
            .fontColor(['#FFB800'])
            .padding(4)
            .borderRadius(10)
            .backgroundColor(C.bgElevated)
            .shadow({ radius: 6, color: C.shadow, offsetY: 2 })
            .margin({ top: -3, right: -3 })
        }
      }
      .width(76)
      .height(76)

      Text(this.c.name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(C.text1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      if (this.showSite) {
        Text(SiteStyle.label(this.c.siteId))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(C.text3)
          .margin({ top: -5 })
      }
    }
    .width(98)
    .padding({ top: 6, bottom: 6 })
    .scale({
      x: this.pressed && !AppEnv.inst.reduceMotion ? 0.94 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.94 : 1
    })
    .animation({ curve: Motion.snappy })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => Nav.openCategory(this.c))
    .gesture(LongPressGesture({ duration: 500 }).onAction(() => {
      const on = CategoryStore.toggleFavorite(this.c);
      promptAction.showToast({ message: on ? `已加入常用：${this.c.name}` : `已移出常用：${this.c.name}` });
    }))
  }
}

/**
 * Featured Spotlight Card for the top 3 flagship channels of each major category group.
 * Uses an atmospheric blurred artwork backdrop + crisp floating icon + bold editorial title.
 */
@ComponentV2
struct FeaturedCategoryCard {
  @Param c: LiveSubCategory = new LiveSubCategory();
  @Local pressed: boolean = false;
  @Local favorite: boolean = false;
  private syncFavorite: () => void = () => {
    this.favorite = CategoryStore.isFavorite(this.c);
  };

  aboutToAppear(): void {
    CategoryStore.subscribeFavorites(this.syncFavorite);
    this.syncFavorite();
  }

  aboutToDisappear(): void {
    CategoryStore.unsubscribeFavorites(this.syncFavorite);
  }

  @Monitor('c')
  onCategory(): void {
    this.syncFavorite();
  }

  build() {
    Stack() {
      // Atmospheric blurred cover background
      NetImage({ src: this.c.pic, fit: ImageFit.Cover, placeholder: C.surface2, decodeW: 80, decodeH: 80 })
        .width('100%')
        .height('100%')
        .blur(38)
        .scale({ x: 1.25, y: 1.25 })

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: [['#6608080A', 0], ['#B308080A', 1]]
        })

      Row({ space: 14 }) {
        Column({ space: 5 }) {
          Row({ space: 5 }) {
            Text('热门频道')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#B3FFFFFF')
              .letterSpacing(0.4)
            if (this.favorite) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(11)
                .fontColor(['#FFB800'])
            }
          }
          Text(this.c.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bolder)
            .fontColor('#F5F5F7')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        NetImage({
          src: this.c.pic,
          radius: 14,
          fit: ImageFit.Cover,
          placeholder: C.surface2,
          decodeW: 80,
          decodeH: 80
        })
          .width(56)
          .height(56)
          .shadow({ radius: 14, color: '#4D000000', offsetY: 6 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 20, right: 18 })
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .height(104)
    .borderRadius(Radius.lg)
    .clip(true)
    .shadow({ radius: 20, color: C.shadow, offsetY: 8 })
    .scale({
      x: this.pressed && !AppEnv.inst.reduceMotion ? 0.96 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.96 : 1
    })
    .animation({ curve: Motion.snappy })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => Nav.openCategory(this.c))
    .gesture(LongPressGesture({ duration: 500 }).onAction(() => {
      const on = CategoryStore.toggleFavorite(this.c);
      promptAction.showToast({ message: on ? `已加入常用：${this.c.name}` : `已移出常用：${this.c.name}` });
    }))
  }
}

/**
 * Retained per-platform category pane (left group rail + right sticky-header channel list)
 * with row-level Repeat virtualScroll so switching or scrolling large category groups
 * only instantiates visible rows.
 */
@ComponentV2
struct SiteCategoryPane {
  @Param site: SiteId = 'huya';
  @Param active: boolean = true;
  @Param compact: boolean = false;
  @Param favorites: LiveSubCategory[] = [];
  @Local activeKey: string = '';
  @Local topRowIsHeader: boolean = true;
  private mounted: boolean = false;
  private scroller: ListScroller = new ListScroller();
  private pendingRail: string = '';
  private visibleKey: string = '';
  private railTimer: number = -1;

  @Computed
  get data(): SiteCategories {
    return CategoryStore.of(this.site);
  }

  @Computed
  get gridCols(): number {
    const totalW = Math.max(360, AppEnv.inst.winWidth - Space.page * 2);
    const railW = this.compact ? (104 + Space.sm) : (164 + Space.xl);
    const listW = Math.max(200, totalW - railW);
    return Math.max(2, Math.floor((listW + 8) / (98 + 8)));
  }

  private buildSection(key: string, title: string, items: LiveSubCategory[], startRowIndex: number): Section {
    const s = new Section();
    s.key = key;
    s.title = title;
    s.count = items.length;
    s.startRowIndex = startRowIndex;
    const cols = this.gridCols;
    const rows: CategoryRow[] = [];

    const hdr = new CategoryRow();
    hdr.key = `${this.site}_hdr_${key}_${items.length}`;
    hdr.sectionKey = key;
    hdr.isHeader = true;
    hdr.headerTitle = title;
    hdr.headerCount = items.length;
    rows.push(hdr);

    let start = 0;
    if (key !== FAV_KEY && !this.compact && items.length >= 4) {
      const feat = new CategoryRow();
      feat.sectionKey = key;
      feat.featured = true;
      feat.items = items.slice(0, 3);
      feat.key = `${this.site}_${key}_feat_${feat.items.map((c: LiveSubCategory) => c.id).join('_')}`;
      rows.push(feat);
      start = 3;
    }
    const showSite = key === FAV_KEY;
    for (let i = start; i < items.length; i += cols) {
      const slice = items.slice(i, i + cols);
      const row = new CategoryRow();
      row.sectionKey = key;
      row.featured = false;
      row.showSite = showSite;
      row.items = slice;
      row.key = `${this.site}_${key}_${i}_${slice.map((c: LiveSubCategory) => `${c.siteId}:${c.id}`).join('_')}`;
      rows.push(row);
    }
    s.rows = rows;
    return s;
  }

  @Computed
  get sections(): Section[] {
    const out: Section[] = [];
    let runningRowIndex = 0;
    const favs = this.favorites;
    if (favs.length > 0) {
      const favSec = this.buildSection(FAV_KEY, '常用', favs, runningRowIndex);
      runningRowIndex += favSec.rows.length;
      out.push(favSec);
    }
    for (const g of this.data.groups) {
      const sec = this.buildSection(g.id, g.name, g.children, runningRowIndex);
      runningRowIndex += sec.rows.length;
      out.push(sec);
    }
    return out;
  }

  @Computed
  get flatRows(): CategoryRow[] {
    const out: CategoryRow[] = [];
    for (const s of this.sections) {
      for (const r of s.rows) {
        out.push(r);
      }
    }
    return out;
  }

  get current(): string {
    if (this.activeKey.length > 0) {
      return this.activeKey;
    }
    return this.sections.length > 0 ? this.sections[0].key : '';
  }

  @Computed
  get currentSection(): Section | undefined {
    const key = this.current;
    for (const s of this.sections) {
      if (s.key === key) {
        return s;
      }
    }
    return this.sections.length > 0 ? this.sections[0] : undefined;
  }

  aboutToAppear(): void {
    this.mounted = true;
    CategoryStore.ensure(this.site);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    if (this.railTimer >= 0) {
      clearTimeout(this.railTimer);
      this.railTimer = -1;
    }
  }

  private jump(index: number): void {
    if (!this.mounted || !this.active || index < 0 || index >= this.sections.length) return;
    const sec = this.sections[index];
    const target = sec.key;
    this.activeKey = target;
    this.topRowIsHeader = true;
    this.pendingRail = target;
    if (this.railTimer >= 0) {
      clearTimeout(this.railTimer);
    }
    this.railTimer = setTimeout(() => {
      if (this.pendingRail === target && this.visibleKey.length > 0) {
        this.activeKey = this.visibleKey;
      }
      this.pendingRail = '';
      this.railTimer = -1;
    }, 900);
    this.scroller.scrollToIndex(sec.startRowIndex, true, ScrollAlign.START);
  }

  @Builder
  groupHeader(title: string, count: number) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bolder)
        .fontColor(C.text1)
      Text(`${count}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(C.text3)
        .fontFeature('"tnum" on')
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 18, bottom: 14, left: 4 })
    .backgroundColor(C.bg)
  }

  @Builder
  rail() {
    List({ space: 6 }) {
      ForEach(this.sections, (s: Section, i: number) => {
        ListItem() {
          Row({ space: 8 }) {
            if (s.key === FAV_KEY) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(14)
                .fontColor(['#FFB800'])
            }
            Text(s.title)
              .fontSize(15)
              .fontWeight(this.current === s.key ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.current === s.key ? C.text1 : C.text2)
              .maxLines(1)
              .layoutWeight(1)
          }
          .width('100%')
          .height(46)
          .padding({ left: 16, right: 14 })
          .borderRadius(Radius.lg)
          .backgroundColor(this.current === s.key ? C.bgElevated : Color.Transparent)
          .shadow(this.current === s.key ? { radius: 14, color: C.shadow, offsetY: 4 } :
            { radius: 0, color: Color.Transparent, offsetY: 0 })
          .animation({ curve: Motion.snappy })
          .onClick(() => this.jump(i))
        }
      }, (s: Section) => `${this.site}_${s.key}`)
    }
    .width(this.compact ? 104 : 164)
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  categoryRowView(row: CategoryRow) {
    if (row.isHeader) {
      this.groupHeader(row.headerTitle, row.headerCount)
    } else if (row.featured) {
      Row({ space: 18 }) {
        ForEach(row.items, (c: LiveSubCategory) => {
          FeaturedCategoryCard({ c: c })
        }, (c: LiveSubCategory) => `feat_${c.siteId}_${c.id}`)
      }
      .width('100%')
      .padding({ bottom: 18 })
    } else {
      Row({ space: 8 }) {
        ForEach(row.items, (c: LiveSubCategory) => {
          SubCategoryTile({ c: c, showSite: row.showSite })
        }, (c: LiveSubCategory) => `${c.siteId}_${c.id}`)
      }
      .width('100%')
      .padding({ bottom: 10 })
    }
  }

  build() {
    Column() {
      if (this.data.loading && this.data.groups.length === 0) {
        Row({ space: this.compact ? Space.sm : Space.xl }) {
          Column({ space: 10 }) {
            ForEach([0, 1, 2, 3, 4], (i: number) => {
              Shimmer({ radius: Radius.lg }).height(46)
            }, (i: number) => `r${i}`)
          }
          .width(this.compact ? 104 : 164)
          Column({ space: 16 }) {
            ForEach([0, 1, 2], (i: number) => {
              Shimmer({ radius: Radius.lg }).height(104)
            }, (i: number) => `g${i}`)
          }
          .layoutWeight(1)
        }
        .width('100%')
      } else if (this.data.groups.length === 0) {
        StateView({
          icon: $r('sys.symbol.square_grid_2x2'),
          title: this.data.error.length > 0 ? this.data.error : '暂无分类',
          actionText: '重试',
          onAction: () => {
            this.data.load();
          }
        })
          .width('100%')
          .margin({ top: 40 })
      } else {
        Row({ space: this.compact ? Space.sm : Space.xl }) {
          this.rail()
          Stack({ alignContent: Alignment.TopStart }) {
            List({ scroller: this.scroller }) {
              ForEach(this.flatRows, (row: CategoryRow) => {
                ListItem() {
                  this.categoryRowView(row)
                }
              }, (r: CategoryRow) => r.key)
            }
            .width('100%')
            .height('100%')
            .cachedCount(2)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .contentEndOffset(Layout.bottomNavInset)
            .onScrollIndex((start: number) => {
              if (!this.mounted || !this.active) return;
              if (start >= 0 && start < this.flatRows.length) {
                const row = this.flatRows[start];
                this.topRowIsHeader = row.isHeader;
                const key = row.sectionKey;
                this.visibleKey = key;
                if (this.pendingRail.length > 0 && key !== this.pendingRail) {
                  return;
                }
                if (key === this.pendingRail && this.railTimer >= 0) {
                  clearTimeout(this.railTimer);
                  this.railTimer = -1;
                }
                this.pendingRail = '';
                this.activeKey = key;
              }
            })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.pendingRail = '';
                if (this.railTimer >= 0) {
                  clearTimeout(this.railTimer);
                  this.railTimer = -1;
                }
              }
            })

            if (this.currentSection !== undefined) {
              Column() {
                this.groupHeader(this.currentSection.title, this.currentSection.count)
              }
              .width('100%')
              .visibility(this.topRowIsHeader ? Visibility.Hidden : Visibility.Visible)
              .hitTestBehavior(HitTestMode.None)
            }
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
export struct CategoryView {
  @Param active: boolean = true;
  @Local site: SiteId = Settings.inst.categorySite;
  @Local drawnSites: SiteId[] = [Settings.inst.categorySite];
  @Local visitedSites: SiteId[] = [Settings.inst.categorySite];
  @Local favorites: LiveSubCategory[] = CategoryStore.favorites();
  private mounted: boolean = false;
  private switchSeq: number = 0;
  private onFavoritesChanged: () => void = () => {
    if (this.mounted && this.active) this.favorites = CategoryStore.favorites();
  };

  get compact(): boolean {
    return Layout.isCompact(AppEnv.inst.winWidth);
  }

  aboutToAppear(): void {
    this.mounted = true;
    CategoryStore.subscribeFavorites(this.onFavoritesChanged);
    this.onFavoritesChanged();
    CategoryStore.ensure(this.site);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.clearSwitch();
    CategoryStore.unsubscribeFavorites(this.onFavoritesChanged);
  }

  @Monitor('active')
  onActive(): void {
    if (!this.active) {
      this.clearSwitch();
    } else {
      this.onFavoritesChanged();
    }
  }

  private clearSwitch(): void {
    this.switchSeq++;
    this.drawnSites = [this.site];
  }

  private finishSwitch(seq: number): void {
    if (this.mounted && this.active && seq === this.switchSeq) {
      this.drawnSites = [this.site];
    }
  }

  private siteOffset(site: SiteId): number {
    return SiteSwitch.offset(Sites.ids, site, this.site, AppEnv.inst.reduceMotion);
  }

  private selectSite(i: number): void {
    const id = Sites.ids[i];
    if (!this.mounted || !this.active || id === undefined || id === this.site) return;
    this.visitedSites = SiteSwitch.include(this.visitedSites, id);
    const seq = ++this.switchSeq;
    if (AppEnv.inst.reduceMotion) {
      this.site = id;
      this.drawnSites = [id];
    } else {
      this.drawnSites = SiteSwitch.include(this.drawnSites, id);
      this.getUIContext().animateTo({
        duration: SiteSwitch.DURATION_MS,
        curve: Motion.snappy,
        onFinish: () => this.finishSwitch(seq)
      }, () => {
        this.site = id;
      });
    }
    Settings.inst.categorySite = id;
    Settings.inst.scheduleSave();
    CategoryStore.ensure(id);
  }

  private onHorizontalSwipe(e: GestureEvent): void {
    const next = SiteSwitch.swipedIndex(Sites.ids, this.site, e.offsetX, e.offsetY);
    if (next >= 0) {
      this.selectSite(next);
    }
  }

  @Builder
  trailing() {
    Segmented({
      glass: true,
      items: SiteSwitch.LABELS,
      selected: Sites.ids.indexOf(this.site),
      onSelect: (i: number) => this.selectSite(i)
    })
  }

  build() {
    Column({ space: Space.lg }) {
      PageTitle({ title: '分类', subtitle: '长按频道可加入「常用」' }) {
        this.trailing()
      }
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(Sites.ids, (site: SiteId) => {
          if (this.visitedSites.includes(site)) {
            SiteCategoryPane({
              site: site,
              active: this.active && site === this.site,
              compact: this.compact,
              favorites: this.favorites
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
      .layoutWeight(1)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Space.page,
      right: Space.page,
      top: AppEnv.inst.statusBarHeight + 20,
      bottom: 0
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 16 })
        .onActionEnd((e: GestureEvent) => this.onHorizontalSwipe(e))
    )
  }
}
