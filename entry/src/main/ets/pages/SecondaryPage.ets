import { AppEnv } from '../app/AppEnv';
import { Nav, Routes } from '../app/Nav';
import { C, Layout, Space } from '../theme/Theme';
import { IconButton } from '../components/Basics';
import { SearchView } from '../views/SearchView';
import { HistoryView } from '../views/HistoryView';
import { SettingsView } from '../views/SettingsView';

/** Secondary destinations own their visibility; mounted does not mean foreground. */
@ComponentV2
export struct SecondaryPage {
  @Param routeName: string = Routes.search;
  @Local shown: boolean = false;
  @Local env: AppEnv = AppEnv.inst;

  get title(): string {
    if (this.routeName === Routes.history) return '观看历史';
    if (this.routeName === Routes.settings) return '设置';
    if (this.routeName === Routes.account) return '账号';
    return '搜索';
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          IconButton({ icon: $r('sys.symbol.chevron_backward'), label: '返回', dim: Layout.touchTarget,
            onTap: () => Nav.back() })
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(C.text1)
        }
        .width('100%')
        .padding({ left: Space.page - 8, right: Space.page, top: this.env.statusBarHeight + 8, bottom: 4 })
        Stack() {
          if (this.routeName === Routes.search) {
            SearchView({ active: this.shown && this.env.foreground, topPadding: Space.md })
          } else if (this.routeName === Routes.history) {
            HistoryView({ topPadding: Space.md })
          } else {
            SettingsView({ active: this.shown && this.env.foreground,
              accountOnly: this.routeName === Routes.account, topPadding: Space.md })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .hideToolBar(true)
    .backgroundColor(C.bg)
    .onShown(() => { this.shown = true; })
    .onHidden(() => { this.shown = false; })
  }
}
