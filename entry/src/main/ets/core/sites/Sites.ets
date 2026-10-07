import { LiveSite } from './LiveSite';
import { HuyaSite } from './HuyaSite';
import { DouyuSite } from './DouyuSite';
import { BiliSite } from './BiliSite';
import { SiteId } from '../model/Models';

export class Sites {
  static readonly huya: HuyaSite = new HuyaSite();
  static readonly douyu: DouyuSite = new DouyuSite();
  static readonly bilibili: BiliSite = new BiliSite();
  static readonly all: LiveSite[] = [Sites.huya, Sites.douyu, Sites.bilibili];
  static readonly ids: SiteId[] = ['huya', 'douyu', 'bilibili'];

  static of(id: SiteId | string): LiveSite {
    if (id === 'douyu') {
      return Sites.douyu;
    }
    if (id === 'bilibili') {
      return Sites.bilibili;
    }
    if (id === 'huya') {
      return Sites.huya;
    }
    throw new Error('不支持的直播平台');
  }

  static isSiteId(id: string): boolean {
    return id === 'huya' || id === 'douyu' || id === 'bilibili';
  }
}

/** A room reference extracted from user input (URL or bare room number). */
export class RoomRef {
  siteId: SiteId = 'huya';
  roomId: string = '';

  constructor(siteId: SiteId, roomId: string) {
    this.siteId = siteId;
    this.roomId = roomId;
  }
}

export class LinkParser {
  /** Returns concrete matches for URLs, or one candidate per site for a bare number. */
  static parse(input: string): RoomRef[] {
    const text = input.trim();
    if (text.length === 0) {
      return [];
    }
    for (const site of Sites.all) {
      const id = site.parseRoomUrl(text);
      if (id.length > 0) {
        return [new RoomRef(site.id, id)];
      }
    }
    if (/^\d{1,12}$/.test(text)) {
      return Sites.ids.map((s: SiteId) => new RoomRef(s, text));
    }
    return [];
  }
}
