/** Shared protocol-layer models (mirrors simple_live_core, plus siteId on every item). */

export type SiteId = 'huya' | 'douyu' | 'bilibili';

export class LiveRoomItem {
  siteId: SiteId = 'huya';
  roomId: string = '';
  title: string = '';
  cover: string = '';
  userName: string = '';
  avatar: string = '';
  online: number = 0;
  area: string = '';

  static of(siteId: SiteId, roomId: string, title: string, cover: string, userName: string,
    online: number): LiveRoomItem {
    const it = new LiveRoomItem();
    it.siteId = siteId;
    it.roomId = roomId;
    it.title = title;
    it.cover = cover;
    it.userName = userName;
    it.online = online;
    return it;
  }
}

export class LiveAnchorItem {
  siteId: SiteId = 'huya';
  roomId: string = '';
  avatar: string = '';
  userName: string = '';
  liveStatus: boolean = false;
}

export class LiveSubCategory {
  siteId: SiteId = 'huya';
  id: string = '';
  name: string = '';
  parentId: string = '';
  pic: string = '';
}

export class LiveCategory {
  id: string = '';
  name: string = '';
  children: LiveSubCategory[] = [];
}

export class RoomPage {
  hasMore: boolean = false;
  items: LiveRoomItem[] = [];

  constructor(items: LiveRoomItem[], hasMore: boolean) {
    this.items = items;
    this.hasMore = hasMore;
  }
}

export class AnchorPage {
  hasMore: boolean = false;
  items: LiveAnchorItem[] = [];

  constructor(items: LiveAnchorItem[], hasMore: boolean) {
    this.items = items;
    this.hasMore = hasMore;
  }
}

export class LiveRoomDetail {
  siteId: SiteId = 'huya';
  roomId: string = '';
  title: string = '';
  cover: string = '';
  userName: string = '';
  userAvatar: string = '';
  online: number = 0;
  introduction: string = '';
  notice: string = '';
  /** true when the anchor is live (not a replay loop). */
  status: boolean = false;
  isRecord: boolean = false;
  url: string = '';
  area: string = '';
  /** Unix seconds when the stream started, 0 if unknown. */
  startTime: number = 0;
  /** Site-specific playback context. */
  data: Object | null = null;
  /** Site-specific danmaku connection args. */
  danmakuArgs: Object | null = null;
}

export class PlayQuality {
  name: string = '';
  /** Higher is better; used to pick the default. */
  sort: number = 0;
  data: Object | null = null;

  constructor(name: string, sort: number, data: Object | null) {
    this.name = name;
    this.sort = sort;
    this.data = data;
  }
}

export class PlayUrls {
  urls: string[] = [];
  headers: Record<string, string> = {};
  /** Actual per-line quality returned by the site, if reported; 0 means unknown. */
  qualityIds: number[] = [];

  constructor(urls: string[], headers: Record<string, string>) {
    this.urls = urls;
    this.headers = headers;
  }
}

export enum LiveMessageType {
  Chat = 0,
  Online = 1,
  SuperChat = 2
}

export class SuperChatMessage {
  userName: string = '';
  face: string = '';
  message: string = '';
  price: number = 0;
  startTime: number = 0;
  endTime: number = 0;
  backgroundColor: string = '#EDF5FF';
  backgroundBottomColor: string = '#2A60B2';
}

export class LiveMessage {
  type: LiveMessageType = LiveMessageType.Chat;
  userName: string = '';
  text: string = '';
  /** 0xRRGGBB; white when the platform sends no color. */
  color: number = 0xffffff;
  online: number = 0;
  superChat: SuperChatMessage | null = null;

  static chat(userName: string, text: string, color: number): LiveMessage {
    const m = new LiveMessage();
    m.userName = userName;
    m.text = text;
    m.color = color;
    return m;
  }

  static onlineCount(n: number): LiveMessage {
    const m = new LiveMessage();
    m.type = LiveMessageType.Online;
    m.online = n;
    return m;
  }

  static sc(sc: SuperChatMessage): LiveMessage {
    const m = new LiveMessage();
    m.type = LiveMessageType.SuperChat;
    m.userName = sc.userName;
    m.text = sc.message;
    m.superChat = sc;
    return m;
  }
}

export const WHITE = 0xffffff;

/** Normalizes 0xRRGGBB / 0xAARRGGBB ints to 0xRRGGBB; non-positive values become white. */
export function normalizeColor(c: number): number {
  if (!(c > 0)) {
    return WHITE;
  }
  return c & 0xffffff;
}
