import { AppEnv } from '../app/AppEnv';
import { C, Layout, Motion, Radius } from '../theme/Theme';
import { DockMaterialModifier, loadDockMaterial } from '../platform/DockMaterial';

class BottomNavEntry {
  key: string;
  label: string;
  icon: Resource;
  selectedIcon: Resource;

  constructor(key: string, label: string, icon: Resource, selectedIcon: Resource) {
    this.key = key;
    this.label = label;
    this.icon = icon;
    this.selectedIcon = selectedIcon;
  }
}

const ITEMS: BottomNavEntry[] = [
  new BottomNavEntry('home', '首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill')),
  new BottomNavEntry('category', '分类', $r('sys.symbol.square_grid_2x2'), $r('sys.symbol.square_fill_grid_2x2')),
  new BottomNavEntry('follow', '关注', $r('sys.symbol.heart'), $r('sys.symbol.heart_fill')),
  new BottomNavEntry('mine', '我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill'))
];

/** A quiet, centered dock. Only touch/focus and selection illuminate a target. */
@ComponentV2
export struct BottomNav {
  @Param selected: string = 'home';
  @Event onSelect: (key: string) => void = () => {};
  @Local pressed: string = '';
  @Local focused: string = '';
  @Local env: AppEnv = AppEnv.inst;
  @Local materialStyle: DockMaterialModifier = new DockMaterialModifier(undefined);
  @Local legacyGlass: boolean = true;
  private materialGeneration: number = 0;

  aboutToAppear(): void {
    this.syncMaterial();
  }

  aboutToDisappear(): void {
    this.materialGeneration++;
  }

  @Monitor('env.reduceMotion', 'env.isDark')
  syncMaterial(): void {
    const generation = ++this.materialGeneration;
    loadDockMaterial(this.env.reduceMotion).then((material: SystemUiMaterial | undefined) => {
      if (generation === this.materialGeneration) {
        this.legacyGlass = material === undefined;
        this.materialStyle = new DockMaterialModifier(material);
      }
    });
  }

  @Builder
  sheen() {
    if (this.legacyGlass) {
      Column() {
        Row()
          .width('86%')
          .height(1)
          .linearGradient({ angle: 90, colors: [[Color.Transparent, 0], [C.navHighlight, 0.5], [Color.Transparent, 1]] })
      }
      .width('100%')
      .padding({ top: 1 })
      .hitTestBehavior(HitTestMode.None)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.dock()
      this.sheen()
    }
    .width('100%')
    .height(Layout.bottomNavHeight)
  }

  @Builder
  dock() {
    Row({ space: 4 }) {
      ForEach(ITEMS, (item: BottomNavEntry) => {
        Button({ type: ButtonType.Capsule }) {
          Column({ space: 2 }) {
            // Keyed by state: a SymbolGlyph does not redraw when only its resource changes.
            ForEach([this.selected === item.key], (on: boolean) => {
              SymbolGlyph(on ? item.selectedIcon : item.icon)
                .fontSize(22)
                .fontColor([on ? C.accent : C.text2])
                .scale({ x: this.pressed === item.key && !this.env.reduceMotion ? 0.9 : 1,
                  y: this.pressed === item.key && !this.env.reduceMotion ? 0.9 : 1 })
                .animation(this.env.reduceMotion ? { duration: 0 } : { curve: Motion.snappy })
            }, (on: boolean) => `${item.key}_${on}`)
            Text(item.label)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selected === item.key ? C.accent : C.text2)
              .maxLines(1)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .id(`nav_${item.key}`)
        .layoutWeight(1)
        .height(48)
        .padding(0)
        .borderRadius(Radius.pill)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .borderWidth(this.focused === item.key ? 1 : 0)
        .borderColor(C.accent)
        .accessibilityText(item.label)
        .accessibilitySelected(this.selected === item.key)
        .onFocus(() => { this.focused = item.key; })
        .onBlur(() => { this.focused = ''; this.pressed = ''; })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) this.pressed = item.key;
          if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.pressed = '';
        })
        .onClick(() => this.onSelect(item.key))
      }, (item: BottomNavEntry) => item.key)
    }
    .width('100%')
    .height(Layout.bottomNavHeight)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .attributeModifier(this.materialStyle)
    .borderRadius(Radius.pill)
  }
}
