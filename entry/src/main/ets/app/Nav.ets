import { LiveRoomItem, LiveSubCategory, SiteId } from '../core/model/Models';
import { AppEnv } from './AppEnv';
import { Motion } from '../theme/Theme';

export class Routes {
  static readonly live: string = 'live';
  static readonly categoryRooms: string = 'categoryRooms';
  static readonly search: string = 'search';
  static readonly history: string = 'history';
  static readonly settings: string = 'settings';
  static readonly account: string = 'account';
}

export class LiveRouteParam {
  siteId: SiteId = 'huya';
  roomId: string = '';
  /** Card data shown instantly while the room detail loads. */
  preview: LiveRoomItem | null = null;
  /** geometryTransition id shared with the originating card cover ('' = no hero animation). */
  heroId: string = '';
  /** Window rect (vp) of the tapped card's cover; the cover morphs into the player. w < 0 = unknown. */
  coverX: number = 0;
  coverY: number = 0;
  coverW: number = -1;
  coverH: number = -1;
}

export class CategoryRouteParam {
  category: LiveSubCategory = new LiveSubCategory();
}

export class Nav {
  static readonly stack: NavPathStack = new NavPathStack();
  /** Navigation id so a PiP window restores into the live room page. */
  static readonly id: string = 'lumen_nav';

  static openLive(item: LiveRoomItem, heroId: string = '', cover: number[] = []): void {
    const p = new LiveRouteParam();
    p.siteId = item.siteId;
    p.roomId = item.roomId;
    p.preview = item;
    // The cross-page geometry morph rendered half-built frames (black regions, clipped glow);
    // the room page now animates as a whole from the card instead (LiveRoomPage.customTransition).
    void heroId;
    p.heroId = '';
    if (cover.length === 4 && cover[2] > 0 && cover[3] > 0) {
      p.coverX = cover[0];
      p.coverY = cover[1];
      p.coverW = cover[2];
      p.coverH = cover[3];
    }
    Nav.pushLive(p);
  }

  static openRoom(siteId: SiteId, roomId: string): void {
    const p = new LiveRouteParam();
    p.siteId = siteId;
    p.roomId = roomId;
    Nav.pushLive(p);
  }

  private static pushLive(p: LiveRouteParam): void {
    const top = Nav.stack.getAllPathName();
    // switching rooms from inside a room replaces instead of stacking rooms
    if (top.length > 0 && top[top.length - 1] === Routes.live) {
      Nav.stack.replacePath({ name: Routes.live, param: p },
        { animated: false, launchMode: LaunchMode.NEW_INSTANCE });
      return;
    }
    Nav.stack.pushPath({ name: Routes.live, param: p }, { launchMode: LaunchMode.NEW_INSTANCE });
  }

  static openCategory(c: LiveSubCategory): void {
    const p = new CategoryRouteParam();
    p.category = c;
    Nav.stack.pushPath({ name: Routes.categoryRooms, param: p });
  }

  private static openSection(name: string): void {
    const paths = Nav.stack.getAllPathName();
    if (paths.length > 0 && paths[paths.length - 1] === name) return;
    Nav.stack.pushPath({ name: name });
  }

  static openSearch(): void { Nav.openSection(Routes.search); }
  static openHistory(): void { Nav.openSection(Routes.history); }
  static openSettings(): void { Nav.openSection(Routes.settings); }
  static openAccount(): void { Nav.openSection(Routes.account); }

  static back(): void {
    Nav.stack.pop();
  }
}
