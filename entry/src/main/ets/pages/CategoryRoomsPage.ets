import { LiveSubCategory, RoomPage } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { CategoryRouteParam, Nav } from '../app/Nav';
import { CategoryStore } from '../app/CategoryStore';
import { RoomFeed } from '../app/RoomFeed';
import { AppEnv } from '../app/AppEnv';
import { C, Radius } from '../theme/Theme';
import { IconButton, NetImage, SiteBadge } from '../components/Basics';
import { RoomGrid } from '../components/RoomGrid';

@ComponentV2
export struct CategoryRoomsPage {
  @Local category: LiveSubCategory = new LiveSubCategory();
  @Local feed: RoomFeed | null = null;
  @Local fav: boolean = false;
  @Local shown: boolean = false;
  @Local env: AppEnv = AppEnv.inst;

  onReady(ctx: NavDestinationContext): void {
    const p = ctx.pathInfo.param as CategoryRouteParam;
    this.category = p.category;
    this.fav = CategoryStore.isFavorite(p.category);
    const c = p.category;
    const f = new RoomFeed((page: number): Promise<RoomPage> => Sites.of(c.siteId).getCategoryRooms(c, page));
    this.feed = f;
    f.load();
  }

  @Builder
  header() {
    Row({ space: 14 }) {
      IconButton({ icon: $r('sys.symbol.chevron_backward'), label: '返回', onTap: () => Nav.back() })
      NetImage({ src: this.category.pic, radius: Radius.md, placeholder: C.surface2 })
        .width(52)
        .height(52)
      Column({ space: 6 }) {
        Text(this.category.name)
          .fontSize(26)
          .fontWeight(FontWeight.Bolder)
          .fontColor(C.text1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SiteBadge({ siteId: this.category.siteId, onMedia: false })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Row({ space: 6 }) {
        SymbolGlyph(this.fav ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
          .fontSize(16)
          .fontColor([this.fav ? '#FFB020' : C.text2])
        Text(this.fav ? '已加入常用' : '加入常用')
          .fontSize(14)
          .fontColor(C.text2)
      }
      .height(44)
      .padding({ left: 14, right: 16 })
      .borderRadius(Radius.pill)
      .backgroundColor(C.surface2)
      .flexShrink(0)
      .onClick(() => {
        this.fav = CategoryStore.toggleFavorite(this.category);
      })
    }
    .width('100%')
    .padding({ bottom: 8 })
  }

  build() {
    NavDestination() {
      if (this.feed !== null) {
        RoomGrid({
          feed: this.feed,
          active: this.shown && this.env.foreground,
          scope: `cat_${this.category.siteId}_${this.category.id}`,
          inset: 0,
          topPadding: AppEnv.inst.statusBarHeight + 18,
          emptyText: '这个分类下暂时没人在播'
        }) {
          this.header()
        }
      }
    }
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor(C.bg)
    .onReady((ctx: NavDestinationContext) => this.onReady(ctx))
    .onShown(() => { this.shown = true; })
    .onHidden(() => { this.shown = false; })
  }
}
