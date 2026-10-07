import {
  AnchorPage,
  LiveCategory,
  LiveRoomDetail,
  LiveSubCategory,
  PlayQuality,
  PlayUrls,
  RoomPage,
  SiteId,
  SuperChatMessage
} from '../model/Models';
import { LiveDanmaku } from '../danmaku/LiveDanmaku';

export abstract class LiveSite {
  abstract readonly id: SiteId;
  abstract readonly name: string;
  /** Short label for chips and badges. */
  abstract readonly shortName: string;

  abstract createDanmaku(): LiveDanmaku;

  abstract getCategories(): Promise<LiveCategory[]>;

  abstract getCategoryRooms(category: LiveSubCategory, page: number): Promise<RoomPage>;

  abstract getRecommendRooms(page: number): Promise<RoomPage>;

  abstract searchRooms(keyword: string, page: number): Promise<RoomPage>;

  abstract searchAnchors(keyword: string, page: number): Promise<AnchorPage>;

  abstract getRoomDetail(roomId: string): Promise<LiveRoomDetail>;

  abstract getPlayQualities(detail: LiveRoomDetail): Promise<PlayQuality[]>;

  abstract getPlayUrls(detail: LiveRoomDetail, quality: PlayQuality): Promise<PlayUrls>;

  abstract getLiveStatus(roomId: string): Promise<boolean>;

  getSuperChats(roomId: string): Promise<SuperChatMessage[]> {
    return Promise.resolve([]);
  }

  /** Extracts a room id from a pasted URL for this site, or '' if it does not match. */
  abstract parseRoomUrl(text: string): string;
}
