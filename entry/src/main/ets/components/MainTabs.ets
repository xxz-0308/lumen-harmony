import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { AppEnv } from '../app/AppEnv';
import { C, Layout } from '../theme/Theme';
import { Log } from '../util/Log';

const KEYS: string[] = ['home', 'category', 'follow', 'mine'];

export function hasHdsTabs(): boolean {
  return canIUse('SystemCapability.UIDesign.HDSComponent.Core');
}

/** HDS owns the floating bar, background sampling, light feedback and safe-area layout. */
@ComponentV2
export struct MainTabs {
  @Param selected: string = 'home';
  @Event onSelect: (key: string) => void = () => {};
  @BuilderParam content: (key: string) => void;
  @Local env: AppEnv = AppEnv.inst;
  @Local index: number = 0;
  @Local materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;
  private controller: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    this.index = Math.max(0, KEYS.indexOf(this.selected));
    this.refreshMaterial();
  }

  /**
   * The supported material types can differ while the system is in power saving or under load.
   * Deciding once at startup could leave the bar on a flat fallback for the whole session, so it
   * is re-read every time the app comes back to the foreground.
   */
  @Monitor('env.foreground')
  refreshMaterial(): void {
    if (!this.env.foreground) {
      return;
    }
    try {
      const supported = hdsMaterial.getSystemMaterialTypes();
      const next = supported.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0 ?
        hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE;
      if (next !== this.materialType) {
        this.materialType = next;
      }
      Log.i('navigation', `HDS floating tabs material=${this.materialType} supported=${supported.join(',')}`);
    } catch (e) {
      Log.w('navigation', 'HDS material policy unavailable; using adaptive material');
    }
  }

  @Monitor('selected')
  syncSelected(): void {
    const next = KEYS.indexOf(this.selected);
    if (next >= 0 && next !== this.index) {
      this.index = next;
      this.controller.changeIndex(next);
    }
  }

  private style(label: string, normal: Resource, selected: Resource, key: string): BottomTabBarStyle {
    return BottomTabBarStyle.of({
      normal: new SymbolGlyphModifier(normal).fontSize(22).fontColor([C.text2]),
      selected: new SymbolGlyphModifier(selected).fontSize(22).fontColor([C.accent])
    }, label).labelStyle({ selectedColor: C.accent, unselectedColor: C.text2,
      font: { size: 11, weight: FontWeight.Medium } }).layoutMode(LayoutMode.VERTICAL).id(`nav_${key}`);
  }

  build() {
    HdsTabs({ barPosition: BarPosition.End, index: this.index, controller: this.controller }) {
      TabContent() { this.content('home') }
        .tabBar(this.style('首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill'), 'home'))
      TabContent() { this.content('category') }
        .tabBar(this.style('分类', $r('sys.symbol.square_grid_2x2'), $r('sys.symbol.square_fill_grid_2x2'), 'category'))
      TabContent() { this.content('follow') }
        .tabBar(this.style('关注', $r('sys.symbol.heart'), $r('sys.symbol.heart_fill'), 'follow'))
      TabContent() { this.content('mine') }
        .tabBar(this.style('我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill'), 'mine'))
    }
    .id('main_tabs')
    .width('100%')
    .height('100%')
    .barMode(BarMode.Fixed)
    .barHeight(Layout.bottomNavHeight)
    .barOverlap(true)
    .barFloatingStyle({
      barWidth: { smallWidth: '100%', mediumWidth: Layout.bottomNavMaxWidth, largeWidth: Layout.bottomNavMaxWidth },
      barSideMargin: 16,
      barBottomMargin: 16,
      // With a zero-height transparent mask the bar's material stopped rendering (labels drawn over
      // raw content; most visible in power saving). A page-coloured fade under the bar restores it
      // and keeps the labels legible either way.
      gradientMask: { maskColor: C.bg, maskHeight: 110 },
      lightColor: this.env.reduceMotion ? Color.Transparent : C.accentHighlight,
      // EXQUISITE was tried for the occasional flat, unlit bar but rendered no material at all on
      // this device; the type is re-read on every foreground instead (see refreshMaterial).
      systemMaterialEffect: { materialType: this.materialType, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE }
    })
    .animationDuration(this.env.reduceMotion ? 0 : 180)
    .scrollable(false)
    .onChange((index: number) => {
      this.index = index;
      if (KEYS[index] !== this.selected) this.onSelect(KEYS[index]);
    })
  }
}
