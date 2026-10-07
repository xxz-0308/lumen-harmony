import { AppEnv } from '../app/AppEnv';
import { Settings } from '../app/Settings';
import { FollowStore } from '../app/Stores';
import { LiveRouteParam, Nav, Routes } from '../app/Nav';
import { C, Layout, Motion } from '../theme/Theme';
import { BottomNav } from '../components/BottomNav';
import { MainTabs, hasHdsTabs } from '../components/MainTabs';
import { HomeView } from '../views/HomeView';
import { CategoryView } from '../views/CategoryView';
import { FollowView } from '../views/FollowView';
import { MineView } from '../views/MineView';
import { SecondaryPage } from './SecondaryPage';
import { LiveRoomPage } from './LiveRoomPage';
import { CategoryRoomsPage } from './CategoryRoomsPage';

/** Keeps a visited section mounted and replays a short lift-in whenever it becomes active. */
@ComponentV2
struct SectionHost {
  @Param active: boolean = false;
  @BuilderParam content: () => void;
  @Local lift: number = 0;

  @Monitor('active')
  onActive(): void {
    if (!this.active || AppEnv.inst.reduceMotion) {
      this.lift = 0;
      return;
    }
    // First-mount content may still be laying out; never expose a blank frame by fading the
    // entire section to zero before it has painted. Keep the short lift-in motion.
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.lift = 8;
    });
    this.getUIContext().animateTo({ curve: Motion.smooth }, () => {
      this.lift = 0;
    });
  }

  build() {
    Stack() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .translate({ y: this.lift })
    .visibility(this.active ? Visibility.Visible : Visibility.None)
  }
}

@Entry
@ComponentV2
struct Index {
  @Local section: string = Settings.inst.startPage === 'history' ? 'mine' : Settings.inst.startPage;
  @Local visited: string[] = [Settings.inst.startPage === 'history' ? 'mine' : Settings.inst.startPage];
  @Local rootShown: boolean = true;
  @Local env: AppEnv = AppEnv.inst;
  private useHds: boolean = hasHdsTabs();
  private legacyHistoryPending: boolean = Settings.inst.startPage === 'history';
  private refreshTimer: number = -1;

  private restoreLegacyStart(): void {
    if (!this.legacyHistoryPending) return;
    // Consume before pushing: popping history must never launch it a second time.
    this.legacyHistoryPending = false;
    Nav.openHistory();
  }

  aboutToAppear(): void {
    // keep follow status fresh while the app is in the foreground
    this.refreshTimer = setInterval(() => {
      if (AppEnv.inst.foreground) {
        FollowStore.inst.refreshAll();
      }
    }, 5 * 60 * 1000);
  }

  aboutToDisappear(): void {
    clearInterval(this.refreshTimer);
  }

  private select(key: string): void {
    if (this.visited.indexOf(key) < 0) {
      this.visited = this.visited.concat([key]);
    }
    this.section = key;
    if (key === 'follow' || key === 'home') {
      FollowStore.inst.refreshAll();
    }
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === Routes.live) {
      LiveRoomPage({ route: param as LiveRouteParam })
    } else if (name === Routes.categoryRooms) {
      CategoryRoomsPage()
    } else if (name === Routes.search || name === Routes.history || name === Routes.settings || name === Routes.account) {
      SecondaryPage({ routeName: name })
    }
  }

  @Builder
  sectionContent(key: string) {
    if (key === 'home' && this.visited.indexOf('home') >= 0) {
      SectionHost({ active: this.section === 'home' }) {
        HomeView({ active: this.section === 'home' && this.rootShown && this.env.foreground,
          onSeeFollows: () => this.select('follow'), onSeeCategories: () => this.select('category') })
      }
    }
    if (key === 'category' && this.visited.indexOf('category') >= 0) {
      SectionHost({ active: this.section === 'category' }) {
        CategoryView()
      }
    }
    if (key === 'follow' && this.visited.indexOf('follow') >= 0) {
      SectionHost({ active: this.section === 'follow' }) {
        FollowView()
      }
    }
    if (key === 'mine' && this.visited.indexOf('mine') >= 0) {
      SectionHost({ active: this.section === 'mine' }) {
        MineView()
      }
    }
  }

  build() {
    Navigation(Nav.stack) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.useHds) {
          MainTabs({ selected: this.section, onSelect: (key: string) => this.select(key),
            content: (key: string) => { this.sectionContent(key); } })
        } else {
          Stack() {
            this.sectionContent('home')
            this.sectionContent('category')
            this.sectionContent('follow')
            this.sectionContent('mine')
          }
          .width('100%')
          .height('100%')
          Row() {
            BottomNav({ selected: this.section, onSelect: (key: string) => this.select(key) })
          }
          .width('100%')
          .constraintSize({ maxWidth: Layout.bottomNavMaxWidth + 32 })
          .padding({ left: 16, right: 16 })
          .margin({ bottom: this.env.navBarHeight + 4 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(C.bg)
    }
    .id(Nav.id)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
    .hideBackButton(true)
    .navDestination(this.pageMap)
    .onNavBarStateChange((visible: boolean) => { this.rootShown = visible; })
    .onAppear(() => this.restoreLegacyStart())
    .backgroundColor(C.bg)
    .width('100%')
    .height('100%')
    .onAreaChange((o: Area, n: Area) => {
      AppEnv.inst.winWidth = n.width as number;
      AppEnv.inst.winHeight = n.height as number;
    })
  }
}
