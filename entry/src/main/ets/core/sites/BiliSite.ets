import { LiveSite } from './LiveSite';
import {
  AnchorPage,
  LiveAnchorItem,
  LiveCategory,
  LiveRoomDetail,
  LiveRoomItem,
  LiveSubCategory,
  PlayQuality,
  PlayUrls,
  RoomPage,
  SiteId,
  SuperChatMessage
} from '../model/Models';
import { Http, httpsUrl, stripTags } from '../common/Http';
import { JNode } from '../common/Json';
import { Md5 } from '../common/Bytes';
import { LiveDanmaku } from '../danmaku/LiveDanmaku';
import { BiliDanmaku, BiliDanmakuArgs, parseBiliSuperChat } from '../danmaku/BiliDanmaku';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';
const REFERER = 'https://live.bilibili.com/';
const MIXIN_TAB: number[] = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38,
  41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
  20, 34, 44, 52
];

class BiliStreamLine {
  url: string;
  qn: number;

  constructor(url: string, qn: number) {
    this.url = url;
    this.qn = qn;
  }
}

export class BiliSite extends LiveSite {
  readonly id: SiteId = 'bilibili';
  readonly name: string = '哔哩哔哩直播';
  readonly shortName: string = 'B站';

  /** Full cookie string after QR login; empty for guests. */
  cookie: string = '';
  userId: number = 0;
  private buvid3: string = '';
  private buvid4: string = '';
  private accessId: string = '';
  private imgKey: string = '';
  private subKey: string = '';
  private wbiFetchedAt: number = 0;

  createDanmaku(): LiveDanmaku {
    return new BiliDanmaku();
  }

  setCookie(cookie: string, userId: number): void {
    this.cookie = cookie;
    this.userId = userId;
    this.buvid3 = '';
    this.buvid4 = '';
    this.imgKey = '';
    this.subKey = '';
    this.wbiFetchedAt = 0;
    this.accessId = '';
  }

  private async ensureBuvid(): Promise<void> {
    if (this.buvid3.length > 0) {
      return;
    }
    const m3 = this.cookie.match(/buvid3=([^;]+)/);
    if (m3 !== null) {
      this.buvid3 = m3[1];
      const m4 = this.cookie.match(/buvid4=([^;]+)/);
      this.buvid4 = m4 !== null ? m4[1] : '';
      return;
    }
    try {
      const res = await Http.getJson('https://api.bilibili.com/x/frontend/finger/spi', undefined,
        { 'user-agent': UA, 'referer': REFERER });
      this.buvid3 = res.path('data.b_3').str();
      this.buvid4 = res.path('data.b_4').str();
    } catch (e) {
      this.buvid3 = '';
    }
  }

  async headers(): Promise<Record<string, string>> {
    await this.ensureBuvid();
    let cookie = this.cookie;
    if (cookie.indexOf('buvid3') < 0 && this.buvid3.length > 0) {
      cookie = `${cookie.length > 0 ? cookie + ';' : ''}buvid3=${this.buvid3};` +
        (this.buvid4.length > 0 ? `buvid4=${this.buvid4};` : '');
    }
    const headers: Record<string, string> = { 'user-agent': UA, 'referer': REFERER };
    if (cookie.length > 0) {
      headers['cookie'] = cookie;
    }
    return headers;
  }

  private async wbiKeys(): Promise<string> {
    const now = Date.now();
    if (this.imgKey.length === 0 || now - this.wbiFetchedAt > 6 * 3600 * 1000) {
      const res = await Http.getJson('https://api.bilibili.com/x/web-interface/nav', undefined, await this.headers());
      const img = res.path('data.wbi_img.img_url').str();
      const sub = res.path('data.wbi_img.sub_url').str();
      const imgKey = img.substring(img.lastIndexOf('/') + 1).split('.')[0];
      const subKey = sub.substring(sub.lastIndexOf('/') + 1).split('.')[0];
      // Anonymous nav may report -101 while still returning valid public WBI image keys.
      if (!/^[a-zA-Z0-9]{32}$/.test(imgKey) || !/^[a-zA-Z0-9]{32}$/.test(subKey)) {
        throw new Error('B站签名参数暂不可用，请重试');
      }
      this.imgKey = imgKey;
      this.subKey = subKey;
      this.wbiFetchedAt = now;
    }
    const origin = this.imgKey + this.subKey;
    let mixin = '';
    for (const i of MIXIN_TAB) {
      if (i < origin.length) {
        mixin += origin.charAt(i);
      }
    }
    return mixin.substring(0, 32);
  }

  /** Adds wts and w_rid to the params per the WBI signing scheme. */
  async wbiSign(params: Record<string, string>): Promise<Record<string, string>> {
    const mixin = await this.wbiKeys();
    const all: Record<string, string> = {};
    const keys = Object.keys(params);
    for (const k of keys) {
      all[k] = params[k];
    }
    all['wts'] = String(Math.floor(Date.now() / 1000));
    const sorted = Object.keys(all).sort();
    const parts: string[] = [];
    for (const k of sorted) {
      const v = all[k].replace(/[!'()*]/g, '');
      all[k] = v;
      parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
    }
    all['w_rid'] = Md5.hex(parts.join('&') + mixin);
    return all;
  }

  private async getAccessId(): Promise<string> {
    if (this.accessId.length > 0) {
      return this.accessId;
    }
    try {
      const html = await Http.getText('https://live.bilibili.com/lol', undefined, await this.headers());
      const m = html.match(/"access_id":"(.*?)"/);
      this.accessId = m !== null ? m[1].replace(/\\/g, '') : '';
    } catch (e) {
      this.accessId = '';
    }
    return this.accessId;
  }

  async getCategories(): Promise<LiveCategory[]> {
    const res = await Http.getJson('https://api.live.bilibili.com/room/v1/Area/getList',
      { 'need_entrance': '1', 'parent_id': '0' }, await this.headers());
    const out: LiveCategory[] = [];
    for (const it of res.get('data').list()) {
      const cat = new LiveCategory();
      cat.id = it.get('id').str();
      cat.name = it.get('name').str();
      for (const s of it.get('list').list()) {
        // "全部xx" pseudo entries (id 0) return no rooms from getList
        if (s.get('id').str() === '0') {
          continue;
        }
        const sub = new LiveSubCategory();
        sub.siteId = 'bilibili';
        sub.id = s.get('id').str();
        sub.name = s.get('name').str();
        sub.parentId = s.get('parent_id').str();
        const pic = s.get('pic').str();
        sub.pic = pic.length > 0 ? `${httpsUrl(pic)}@100w.png` : '';
        cat.children.push(sub);
      }
      out.push(cat);
    }
    return out;
  }

  private parseList(list: JNode): LiveRoomItem[] {
    const items: LiveRoomItem[] = [];
    for (const it of list.list()) {
      const room = LiveRoomItem.of('bilibili', it.get('roomid').str(), it.get('title').str(),
        `${httpsUrl(it.get('cover').str())}@400w.jpg`, it.get('uname').str(), it.get('online').num());
      room.avatar = `${httpsUrl(it.get('face').str())}@100w.jpg`;
      room.area = it.get('area_name').str();
      items.push(room);
    }
    return items;
  }

  async getCategoryRooms(category: LiveSubCategory, page: number): Promise<RoomPage> {
    // The web getList endpoint is frequently risk-controlled (-352) for guests; v3 is unsigned and stable.
    const v3 = await Http.getJson('https://api.live.bilibili.com/room/v3/area/getRoomList', {
      'platform': 'web', 'parent_area_id': category.parentId, 'area_id': category.id, 'page': String(page),
      'page_size': '30', 'sort_type': 'online'
    }, await this.headers());
    if (v3.get('code').int() === 0) {
      const items = this.parseList(v3.path('data.list'));
      return new RoomPage(items, items.length > 0 && v3.path('data.has_more').int(1) === 1);
    }
    const params = await this.wbiSign({
      'platform': 'web', 'parent_area_id': category.parentId, 'area_id': category.id, 'sort_type': '',
      'page': String(page), 'w_webid': await this.getAccessId()
    });
    const res = await Http.getJson('https://api.live.bilibili.com/xlive/web-interface/v1/second/getList', params,
      await this.headers());
    return new RoomPage(this.parseList(res.path('data.list')), res.path('data.has_more').int() === 1);
  }

  async getRecommendRooms(page: number): Promise<RoomPage> {
    const params = await this.wbiSign({ 'platform': 'web', 'sort': 'online', 'page_size': '30', 'page': String(page) });
    const res = await Http.getJson('https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea', params,
      await this.headers());
    const items = this.parseList(res.path('data.list'));
    return new RoomPage(items, items.length > 0);
  }

  private async search(type: string, keyword: string, page: number): Promise<JNode> {
    const url = `https://api.bilibili.com/x/web-interface/search/type?context=&search_type=${type}&cover_type=user_cover`;
    return Http.getJson(url, {
      'order': '', 'keyword': keyword, 'category_id': '', '__refresh__': '', '_extra': '', 'highlight': '0',
      'single_column': '0', 'page': String(page)
    }, await this.headers());
  }

  async searchRooms(keyword: string, page: number): Promise<RoomPage> {
    const res = await this.search('live', keyword, page);
    const items: LiveRoomItem[] = [];
    for (const it of res.path('data.result.live_room').list()) {
      const room = LiveRoomItem.of('bilibili', it.get('roomid').str(), stripTags(it.get('title').str()),
        `${httpsUrl(it.get('cover').str())}@400w.jpg`, stripTags(it.get('uname').str()), it.get('online').num());
      room.avatar = `${httpsUrl(it.get('uface').str())}@100w.jpg`;
      room.area = it.get('cate_name').str();
      items.push(room);
    }
    return new RoomPage(items, items.length >= 40);
  }

  async searchAnchors(keyword: string, page: number): Promise<AnchorPage> {
    const res = await this.search('live_user', keyword, page);
    const items: LiveAnchorItem[] = [];
    for (const it of res.path('data.result').list()) {
      const a = new LiveAnchorItem();
      a.siteId = 'bilibili';
      a.roomId = it.get('roomid').str();
      a.avatar = `${httpsUrl(it.get('uface').str())}@100w.jpg`;
      a.userName = stripTags(it.get('uname').str());
      a.liveStatus = it.get('is_live').bool();
      items.push(a);
    }
    return new AnchorPage(items, items.length >= 40);
  }

  async getRoomDetail(roomId: string): Promise<LiveRoomDetail> {
    const infoParams = await this.wbiSign({ 'room_id': roomId });
    const infoRes = await Http.getJson('https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom',
      infoParams, await this.headers());
    const info = infoRes.get('data');
    const room = info.get('room_info');
    if (infoRes.get('code').int() !== 0 || !room.isObject) {
      throw new Error('B站房间信息获取失败，请确认房间号后重试');
    }
    const realId = room.get('room_id').str(roomId);
    let danmu = new JNode(undefined);
    try {
      const danmuParams = await this.wbiSign({ 'id': realId, 'type': '0' });
      const danmuRes = await Http.getJson('https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo',
        danmuParams, await this.headers());
      if (danmuRes.get('code').int() === 0 && danmuRes.get('data').isObject) {
        danmu = danmuRes.get('data');
      }
    } catch (e) {
      // Chat is optional; room detail and playback remain usable when its endpoint fails.
    }
    const hosts = danmu.get('host_list').list();

    const d = new LiveRoomDetail();
    d.siteId = 'bilibili';
    d.roomId = realId;
    d.title = room.get('title').str();
    d.cover = httpsUrl(room.get('cover').str());
    d.userName = info.path('anchor_info.base_info.uname').str();
    d.userAvatar = `${httpsUrl(info.path('anchor_info.base_info.face').str())}@100w.jpg`;
    d.online = room.get('online').num();
    d.status = room.get('live_status').int() === 1;
    d.introduction = room.get('description').str();
    d.area = room.get('area_name').str();
    d.startTime = room.get('live_start_time').int();
    d.url = `https://live.bilibili.com/${roomId}`;
    const args = new BiliDanmakuArgs();
    args.roomId = Number(realId);
    args.uid = this.userId;
    args.token = danmu.get('token').str();
    args.host = hosts.length > 0 ? hosts[0].get('host').str() : 'broadcastlv.chat.bilibili.com';
    args.buvid = this.buvid3;
    d.danmakuArgs = args;
    return d;
  }

  private async playInfo(roomId: string, qn: number): Promise<JNode> {
    const q: Record<string, string> = {
      'room_id': roomId, 'protocol': '0,1', 'format': '0,1,2', 'codec': '0', 'platform': 'web'
    };
    if (qn > 0) {
      q['qn'] = String(qn);
    }
    const res = await Http.getJson('https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo', q,
      await this.headers());
    return res.path('data.playurl_info.playurl');
  }

  async getPlayQualities(detail: LiveRoomDetail): Promise<PlayQuality[]> {
    const play = await this.playInfo(detail.roomId, 0);
    const names = new Map<number, string>();
    for (const g of play.get('g_qn_desc').list()) {
      names.set(g.get('qn').int(), g.get('desc').str());
    }
    const out: PlayQuality[] = [];
    const accept = play.path('stream.0.format.0.codec.0.accept_qn').list();
    for (const a of accept) {
      const qn = a.int();
      out.push(new PlayQuality(names.get(qn) ?? `${qn}`, qn, qn));
    }
    return out;
  }

  async getPlayUrls(detail: LiveRoomDetail, quality: PlayQuality): Promise<PlayUrls> {
    const play = await this.playInfo(detail.roomId, quality.data as number);
    const flv: BiliStreamLine[] = [];
    const hls: BiliStreamLine[] = [];
    for (const stream of play.get('stream').list()) {
      const isFlv = stream.get('protocol_name').str() === 'http_stream';
      for (const format of stream.get('format').list()) {
        for (const codec of format.get('codec').list()) {
          const base = codec.get('base_url').str();
          const qn = codec.get('current_qn').int(play.get('current_qn').int());
          for (const u of codec.get('url_info').list()) {
            const url = `${u.get('host').str()}${base}${u.get('extra').str()}`;
            (isFlv ? flv : hls).push(new BiliStreamLine(url, qn));
          }
        }
      }
    }
    // mcdn (P2P edge) lines are flaky; keep them last within each protocol
    const rank = (line: BiliStreamLine): number => line.url.indexOf('mcdn') >= 0 ? 1 : 0;
    flv.sort((a: BiliStreamLine, b: BiliStreamLine) => rank(a) - rank(b));
    hls.sort((a: BiliStreamLine, b: BiliStreamLine) => rank(a) - rank(b));
    const lines = flv.concat(hls);
    const result = new PlayUrls(lines.map((line: BiliStreamLine) => line.url),
      { 'referer': 'https://live.bilibili.com', 'user-agent': UA });
    result.qualityIds = lines.map((line: BiliStreamLine) => line.qn);
    return result;
  }

  async getLiveStatus(roomId: string): Promise<boolean> {
    const res = await Http.getJson('https://api.live.bilibili.com/room/v1/Room/get_info', { 'room_id': roomId },
      await this.headers());
    return res.path('data.live_status').int() === 1;
  }

  async getSuperChats(roomId: string): Promise<SuperChatMessage[]> {
    const res = await Http.getJson('https://api.live.bilibili.com/av/v1/SuperChat/getMessageList',
      { 'room_id': roomId }, await this.headers());
    const out: SuperChatMessage[] = [];
    for (const it of res.path('data.list').list()) {
      out.push(parseBiliSuperChat(it));
    }
    return out;
  }

  parseRoomUrl(text: string): string {
    const m = text.match(/live\.bilibili\.com\/(?:h5\/|blanc\/)?(\d+)/);
    return m !== null ? m[1] : '';
  }
}
