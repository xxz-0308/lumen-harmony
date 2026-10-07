import { LiveRoomItem, SiteId } from '../core/model/Models';
import { Sites } from '../core/sites/Sites';
import { RoomFeed } from './RoomFeed';

/** Long-lived feeds so switching sections or sites keeps loaded pages and scroll-free state. */
export class Feeds {
  private static recommend: Map<string, RoomFeed> = new Map<string, RoomFeed>();

  static recommendOf(site: SiteId): RoomFeed {
    let f = Feeds.recommend.get(site);
    if (f === undefined) {
      f = new RoomFeed((page: number) => Sites.of(site).getRecommendRooms(page));
      Feeds.recommend.set(site, f);
    }
    return f;
  }

  static heroFallback(site: SiteId): LiveRoomItem[] {
    return Feeds.recommendOf(site).items.slice(0, 5);
  }
}
