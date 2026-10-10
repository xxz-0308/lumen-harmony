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

const FAV_KEY: string = '__fav__';

class Section {
  key: string = '';
  title: string = '';
  items: LiveSubCategory[] = [];
}

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
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        NetImage({ src: this.c.pic, radius: Radius.md, fit: ImageFit.Cover, placeholder: C.surface2 })
          .width(64)
          .height(64)
        if (this.favorite) {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(12)
            .fontColor(['#FFC94D'])
            .padding(3)
            .borderRadius(9)
            .backgroundColor('#8C000000')
            .margin(-4)
        }
      }
      .width(64)
      .height(64)
      Text(this.c.name)
        .fontSize(12)
        .fontColor(C.text1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.showSite) {
        Text(SiteStyle.label(this.c.siteId))
          .fontSize(10)
          .fontColor(SiteStyle.color(this.c.siteId))
          .margin({ top: -4 })
      }
    }
    .width(92)
    .padding({ top: 10, bottom: 10 })
    .borderRadius(Radius.md)
    .backgroundColor(this.pressed ? C.surface2 : Color.Transparent)
    .scale({ x: this.pressed && !AppEnv.inst.reduceMotion ? 0.94 : 1,
      y: this.pressed && !AppEnv.inst.reduceMotion ? 0.94 : 1 })
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

@ComponentV2
export struct CategoryView {
  @Param active: boolean = true;
  @Local site: SiteId = Settings.inst.categorySite;
  @Local selectedSite: SiteId = Settings.inst.categorySite;
  private mounted: boolean = false;
  private switchSeq: number = 0;
  private listY: number = 0;
  private pendingY: number = -1;
  private listReady: boolean = false;
  private alignTimer: number = -1;
  @Local activeKey: string = '';
  @Local favorites: LiveSubCategory[] = CategoryStore.favorites();
  private scroller: ListScroller = new ListScroller();
  private pendingRail: string = '';
  private visibleKey: string = '';
  private railTimer: number = -1;
  private onFavoritesChanged: () => void = () => {
    if (this.mounted && this.active) this.favorites = CategoryStore.favorites();
  };

  @Computed
  get data(): SiteCategories {
    return CategoryStore.of(this.site);
  }

  @Computed
  get sections(): Section[] {
    const out: Section[] = [];
    const favs = this.favorites;
    if (favs.length > 0) {
      const f = new Section();
      f.key = FAV_KEY;
      f.title = '常用';
      f.items = favs;
      out.push(f);
    }
    for (const g of this.data.groups) {
      const s = new Section();
      s.key = g.id;
      s.title = g.name;
      s.items = g.children;
      out.push(s);
    }
    return out;
  }

  aboutToAppear(): void {
    this.mounted = true;
    this.site = this.selectedSite;
    CategoryStore.subscribeFavorites(this.onFavoritesChanged);
    this.onFavoritesChanged();
    CategoryStore.ensure(this.site);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.switchSeq++;
    this.clearAlignment();
    CategoryStore.unsubscribeFavorites(this.onFavoritesChanged);
    if (this.railTimer >= 0) {
      clearTimeout(this.railTimer);
      this.railTimer = -1;
    }
  }

  @Monitor('active')
  onActive(): void {
    if (!this.active) {
      this.switchSeq++;
      this.clearAlignment();
      this.listReady = false;
      if (this.railTimer >= 0) clearTimeout(this.railTimer);
      this.railTimer = -1;
      this.pendingRail = '';
      if (this.mounted && this.site !== this.selectedSite) this.applySite(this.selectedSite);
      this.contentX = 0;
      this.contentFade = 1;
    } else {
      this.onFavoritesChanged();
    }
  }

  @Monitor('sections')
  onSections(): void {
    this.alignWhenReady();
  }

  private clearAlignment(): void {
    if (this.alignTimer >= 0) clearTimeout(this.alignTimer);
    this.alignTimer = -1;
  }

  private alignWhenReady(): void {
    if (!this.mounted || !this.active || !this.listReady || this.pendingY < 0 || this.data.groups.length === 0) return;
    this.clearAlignment();
    const seq = this.switchSeq;
    this.alignTimer = setTimeout(() => {
      this.alignTimer = -1;
      if (!this.mounted || !this.active || !this.listReady || seq !== this.switchSeq || this.pendingY < 0) return;
      const y = this.pendingY;
      this.pendingY = -1;
      this.scroller.scrollTo({ xOffset: 0, yOffset: y, animation: false });
      this.listY = Math.max(0, this.scroller.currentOffset().yOffset);
    }, 0);
  }

  /** Slide offset and fade of the category content while switching platforms. */
  @Local contentX: number = 0;
  @Local contentFade: number = 1;

  private selectSite(i: number): void {
    const next = Sites.ids[i];
    if (!this.mounted || !this.active || next === undefined || next === this.selectedSite) return;
    const seq = ++this.switchSeq;
    this.clearAlignment();
    this.selectedSite = next;
    Settings.inst.categorySite = next;
    Settings.inst.scheduleSave();
    CategoryStore.ensure(next);
    if (AppEnv.inst.reduceMotion || next === this.site) {
      if (next !== this.site) this.applySite(next);
      this.getUIContext().animateTo({ duration: AppEnv.inst.reduceMotion ? 0 : 220, curve: Motion.snappy }, () => {
        this.contentX = 0;
        this.contentFade = 1;
      });
      return;
    }
    const dir = i > Sites.ids.indexOf(this.site) ? 1 : -1;
    this.getUIContext().animateTo({ duration: 100, curve: Curve.EaseIn, onFinish: () => {
      if (!this.mounted || !this.active || seq !== this.switchSeq) return;
      this.applySite(next);
      this.contentX = 28 * dir;
      this.getUIContext().animateTo({ duration: 220, curve: Motion.snappy }, () => {
        this.contentX = 0;
        this.contentFade = 1;
      });
    } }, () => {
      this.contentX = -28 * dir;
      this.contentFade = 0;
    });
  }

  private applySite(next: SiteId): void {
    this.pendingY = this.listY;
    this.site = next;
    CategoryStore.ensure(this.site);
    if (this.data.groups.length === 0) this.listReady = false;
    this.activeKey = '';
    this.pendingRail = '';
    this.visibleKey = '';
    if (this.railTimer >= 0) {
      clearTimeout(this.railTimer);
      this.railTimer = -1;
    }
    this.alignWhenReady();
  }

  private jump(index: number): void {
    if (!this.mounted || !this.active || index < 0 || index >= this.sections.length) return;
    this.pendingY = -1;
    this.clearAlignment();
    const target = this.sections[index].key;
    this.activeKey = target;
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
    this.scroller.scrollToIndex(index, true, ScrollAlign.START);
  }

  @Builder
  trailing() {
    Segmented({
      glass: true,
      items: ['虎牙', '斗鱼', 'B站'],
      selected: Sites.ids.indexOf(this.selectedSite),
      onSelect: (i: number) => this.selectSite(i)
    })
  }

  @Builder
  groupHeader(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor(C.text1)
      .width('100%')
      .padding({ top: 14, bottom: 6, left: 4 })
      .backgroundColor(C.bg)
  }

  @Builder
  rail() {
    List({ space: 4 }) {
      ForEach(this.sections, (s: Section, i: number) => {
        ListItem() {
          Row({ space: 6 }) {
            if (s.key === FAV_KEY) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(13)
                .fontColor(['#FFB020'])
            }
            Text(s.title)
              .fontSize(14)
              .fontWeight(this.current === s.key ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.current === s.key ? C.accent : C.text2)
              .maxLines(1)
          }
          .width('100%')
          .height(44)
          .padding({ left: 14 })
          .borderRadius(Radius.md)
          .backgroundColor(this.current === s.key ? C.accentSoft : Color.Transparent)
          .animation({ curve: Motion.snappy })
          .onClick(() => this.jump(i))
        }
      }, (s: Section) => `${this.site}_${s.key}`)
    }
    .width(Layout.isCompact(AppEnv.inst.winWidth) ? 100 : 150)
    .height('100%')
    .scrollBar(BarState.Off)
  }

  get current(): string {
    if (this.activeKey.length > 0) {
      return this.activeKey;
    }
    return this.sections.length > 0 ? this.sections[0].key : '';
  }

  build() {
    Column({ space: Space.lg }) {
      PageTitle({ title: '分类', subtitle: '长按分类可加入「常用」' }) {
        this.trailing()
      }
      Column() {
        if (this.data.loading && this.data.groups.length === 0) {
          Row({ space: Layout.isCompact(AppEnv.inst.winWidth) ? Space.sm : Space.xl }) {
            Column({ space: 10 }) {
              ForEach([0, 1, 2, 3, 4], (i: number) => {
                Shimmer({ radius: Radius.md })
                  .height(40)
              }, (i: number) => `r${i}`)
            }
            .width(Layout.isCompact(AppEnv.inst.winWidth) ? 100 : 150)
            Column({ space: 16 }) {
              ForEach([0, 1, 2], (i: number) => {
                Shimmer({ radius: Radius.md })
                  .height(92)
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
          Row({ space: Layout.isCompact(AppEnv.inst.winWidth) ? Space.sm : Space.xl }) {
            this.rail()
            List({ scroller: this.scroller }) {
              ForEach(this.sections, (s: Section) => {
                ListItemGroup({ header: this.groupHeader(s.title) }) {
                  ListItem() {
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(s.items, (c: LiveSubCategory) => {
                        SubCategoryTile({ c: c, showSite: s.key === FAV_KEY })
                      }, (c: LiveSubCategory) => `${s.key}_${c.siteId}_${c.id}`)
                    }
                    .width('100%')
                  }
                }
              }, (s: Section) => `${this.site}_${s.key}_${s.items.length}`)
            }
            .layoutWeight(1)
            .height('100%')
            .sticky(StickyStyle.Header)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .contentEndOffset(Layout.bottomNavInset)
            .onVisibleAreaChange([0], (visible: boolean) => {
              this.listReady = visible;
              if (visible) this.alignWhenReady();
            })
            .onDidScroll(() => {
              if (this.active && this.pendingY < 0) this.listY = Math.max(0, this.scroller.currentOffset().yOffset);
            })
            .onScrollIndex((start: number) => {
              if (!this.mounted || !this.active) return;
              this.alignWhenReady();
              if (start >= 0 && start < this.sections.length) {
                const key = this.sections[start].key;
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
                this.pendingY = -1;
                this.clearAlignment();
                this.pendingRail = '';
                if (this.railTimer >= 0) {
                  clearTimeout(this.railTimer);
                  this.railTimer = -1;
                }
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(VerticalAlign.Top)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .translate({ x: this.contentX })
      .opacity(this.contentFade)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Space.page,
      right: Space.page,
      top: AppEnv.inst.statusBarHeight + 24,
      bottom: 0
    })
  }
}
