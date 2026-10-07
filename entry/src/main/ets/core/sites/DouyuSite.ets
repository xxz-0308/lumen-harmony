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
  SiteId
} from '../model/Models';
import { Http, htmlUnescape, httpsUrl, UA_PC } from '../common/Http';
import { JNode } from '../common/Json';
import { Md5, randomHex } from '../common/Bytes';
import { LiveDanmaku } from '../danmaku/LiveDanmaku';
import { DouyuDanmaku } from '../danmaku/DouyuDanmaku';

const DID = '10000000000000000000000000001501';
const SEARCH_DID = randomHex(32);

class DouyuEncryption {
  key: string = '';
  randStr: string = '';
  encTime: number = 0;
  isSpecial: boolean = false;
  encData: string = '';
  expireAt: number = 0;
}

class DouyuQualityData {
  rate: number = 0;
  cdns: string[] = [];
}

export class DouyuSite extends LiveSite {
  readonly id: SiteId = 'douyu';
  readonly name: string = '斗鱼直播';
  readonly shortName: string = '斗鱼';
  private enc: DouyuEncryption | null = null;

  createDanmaku(): LiveDanmaku {
    return new DouyuDanmaku();
  }

  private static headers(roomId: string): Record<string, string> {
    return { 'referer': `https://www.douyu.com/${roomId}`, 'user-agent': UA_PC };
  }

  async getCategories(): Promise<LiveCategory[]> {
    const res = await Http.getJson('https://m.douyu.com/api/cate/list');
    const subs = res.path('data.cate2Info').list();
    const out: LiveCategory[] = [];
    for (const c1 of res.path('data.cate1Info').list()) {
      const cat = new LiveCategory();
      cat.id = c1.get('cate1Id').str();
      cat.name = c1.get('cate1Name').str();
      for (const c2 of subs) {
        if (c2.get('cate1Id').str() !== cat.id) {
          continue;
        }
        const sub = new LiveSubCategory();
        sub.siteId = 'douyu';
        sub.id = c2.get('cate2Id').str();
        sub.name = c2.get('cate2Name').str();
        sub.parentId = cat.id;
        sub.pic = httpsUrl(c2.get('icon').str());
        cat.children.push(sub);
      }
      out.push(cat);
    }
    out.sort((a: LiveCategory, b: LiveCategory) => Number(a.id) - Number(b.id));
    return out;
  }

  private parseRl(res: JNode): RoomPage {
    const items: LiveRoomItem[] = [];
    for (const it of res.path('data.rl').list()) {
      if (it.get('type').int() !== 1) {
        continue;
      }
      const room = LiveRoomItem.of('douyu', it.get('rid').str(), it.get('rn').str(), httpsUrl(it.get('rs16').str()),
        it.get('nn').str(), it.get('ol').num());
      const av = it.get('av').str();
      room.avatar = av.startsWith('http') || av.startsWith('//') ? httpsUrl(av) :
        (av.length > 0 ? `https://apic.douyucdn.cn/upload/${av}_middle.jpg` : '');
      room.area = it.get('c2name').str();
      items.push(room);
    }
    return new RoomPage(items, res.path('data.pgcnt').num() > 0 && items.length > 0);
  }

  async getCategoryRooms(category: LiveSubCategory, page: number): Promise<RoomPage> {
    const res = await Http.getJson(`https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.id}/${page}`);
    const r = this.parseRl(res);
    r.hasMore = page < res.path('data.pgcnt').num();
    return r;
  }

  async getRecommendRooms(page: number): Promise<RoomPage> {
    const res = await Http.getJson(`https://www.douyu.com/japi/weblist/apinc/allpage/6/${page}`);
    const r = this.parseRl(res);
    r.hasMore = page < res.path('data.pgcnt').num();
    return r;
  }

  private static searchHeaders(): Record<string, string> {
    return {
      'user-agent': UA_PC,
      'referer': 'https://www.douyu.com/search/',
      'cookie': `dy_did=${SEARCH_DID};acf_did=${SEARCH_DID}`
    };
  }

  async searchRooms(keyword: string, page: number): Promise<RoomPage> {
    const res = await Http.getJson('https://www.douyu.com/japi/search/api/searchShow',
      { 'kw': keyword, 'page': String(page), 'pageSize': '20' }, DouyuSite.searchHeaders());
    if (res.get('error').int() !== 0) {
      throw new Error(res.get('msg').str('斗鱼搜索失败'));
    }
    const items: LiveRoomItem[] = [];
    for (const it of res.path('data.relateShow').list()) {
      const room = LiveRoomItem.of('douyu', it.get('rid').str(), it.get('roomName').str(),
        httpsUrl(it.get('roomSrc').str()), it.get('nickName').str(), DouyuSite.parseHot(it.get('hot').str()));
      room.avatar = httpsUrl(it.get('avatar').str());
      room.area = it.get('cateName').str();
      items.push(room);
    }
    return new RoomPage(items, items.length > 0);
  }

  async searchAnchors(keyword: string, page: number): Promise<AnchorPage> {
    const res = await Http.getJson('https://www.douyu.com/japi/search/api/searchUser',
      { 'kw': keyword, 'page': String(page), 'pageSize': '20', 'filterType': '1' }, DouyuSite.searchHeaders());
    const items: LiveAnchorItem[] = [];
    for (const it of res.path('data.relateUser').list()) {
      const info = it.get('anchorInfo');
      const a = new LiveAnchorItem();
      a.siteId = 'douyu';
      a.roomId = info.get('rid').str();
      a.avatar = httpsUrl(info.get('avatar').str());
      a.userName = info.get('nickName').str();
      a.liveStatus = info.get('isLive').int() === 1 && info.get('roomType').int() === 0;
      items.push(a);
    }
    return new AnchorPage(items, items.length > 0);
  }

  private async getBetard(roomId: string): Promise<JNode> {
    const res = await Http.getJson(`https://www.douyu.com/betard/${roomId}`, undefined, DouyuSite.headers(roomId));
    if (res.get('error').int() !== 0 || !res.get('room').isObject) {
      throw new Error('斗鱼房间信息获取失败，请确认房间号后重试');
    }
    return res.get('room');
  }

  async getRoomDetail(roomId: string): Promise<LiveRoomDetail> {
    const room = await this.getBetard(roomId);
    const d = new LiveRoomDetail();
    d.siteId = 'douyu';
    d.roomId = room.get('room_id').str(roomId);
    d.title = room.get('room_name').str();
    d.cover = httpsUrl(room.get('room_pic').str());
    d.userName = room.get('owner_name').str();
    d.userAvatar = httpsUrl(room.get('owner_avatar').str());
    d.online = room.path('room_biz_all.hot').num();
    d.introduction = room.get('show_details').str();
    d.status = room.get('show_status').int() === 1 && room.get('videoLoop').int() !== 1;
    d.isRecord = room.get('videoLoop').int() === 1;
    d.area = room.get('cate2_name').str(room.get('second_lvl_name').str());
    d.startTime = room.get('show_time').int();
    d.url = `https://www.douyu.com/${roomId}`;
    d.danmakuArgs = d.roomId;
    return d;
  }

  private async encryption(): Promise<DouyuEncryption> {
    const now = Math.floor(Date.now() / 1000);
    if (this.enc !== null && this.enc.expireAt - 60 > now) {
      return this.enc;
    }
    const res = await Http.getJson('https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption',
      { 'did': DID }, { 'referer': 'https://www.douyu.com/', 'user-agent': UA_PC });
    if (res.get('error').int() !== 0) {
      throw new Error(res.get('msg').str('斗鱼签名失败'));
    }
    const data = res.get('data');
    const e = new DouyuEncryption();
    e.key = data.get('key').str();
    e.randStr = data.get('rand_str').str();
    e.encTime = data.get('enc_time').int();
    if (e.encTime < 0 || e.encTime > 1000) {
      throw new Error('斗鱼签名参数异常');
    }
    e.isSpecial = data.get('is_special').int() === 1;
    e.encData = data.get('enc_data').str();
    e.expireAt = data.get('expire_at').int(now + 300);
    this.enc = e;
    return e;
  }

  private async h5Play(roomId: string, cdn: string, rate: number): Promise<JNode> {
    const e = await this.encryption();
    const ts = Math.floor(Date.now() / 1000);
    let secret = e.randStr;
    for (let i = 0; i < e.encTime; i++) {
      secret = Md5.hex(secret + e.key);
    }
    const auth = Md5.hex(secret + e.key + (e.isSpecial ? '' : `${roomId}${ts}`));
    const res = await Http.postForm(`https://www.douyu.com/lapi/live/getH5PlayV1/${roomId}`, {
      'enc_data': e.encData,
      'tt': String(ts),
      'did': DID,
      'auth': auth,
      'cdn': cdn,
      'rate': String(rate),
      'hevc': '0',
      'fa': '0',
      'ive': '0',
      'iar': '0',
      'ver': '219032101'
    }, DouyuSite.headers(roomId));
    if (res.get('error').int() !== 0) {
      this.enc = null;
      throw new Error(res.get('msg').str('斗鱼播放地址获取失败'));
    }
    return res.get('data');
  }

  async getPlayQualities(detail: LiveRoomDetail): Promise<PlayQuality[]> {
    const data = await this.h5Play(detail.roomId, '', -1);
    const cdns: string[] = [];
    for (const c of data.get('cdnsWithName').list()) {
      cdns.push(c.get('cdn').str());
    }
    // scdn lines are the least reliable; try them last
    cdns.sort((a: string, b: string) => (a.startsWith('scdn') ? 1 : 0) - (b.startsWith('scdn') ? 1 : 0));
    const out: PlayQuality[] = [];
    for (const r of data.get('multirates').list()) {
      const qd = new DouyuQualityData();
      qd.rate = r.get('rate').int();
      qd.cdns = cdns;
      // rate 0 is the source stream; higher bit rates sort first otherwise
      out.push(new PlayQuality(r.get('name').str(), qd.rate === 0 ? 1e9 : r.get('bit').num(qd.rate), qd));
    }
    return out;
  }

  async getPlayUrls(detail: LiveRoomDetail, quality: PlayQuality): Promise<PlayUrls> {
    const qd = quality.data as DouyuQualityData;
    let unavailable = 0;
    // The CDNs are independent; signing them one by one adds their latencies together.
    const signed = await Promise.all(qd.cdns.map(async (cdn: string): Promise<string> => {
      try {
        const data = await this.h5Play(detail.roomId, cdn, qd.rate);
        // A room may still be marked live while the play API says the stream is offline.
        // Such signed FLV addresses return CDN 404; trying lines/recovery only flickers.
        if (data.get('streamStatus').exists && data.get('streamStatus').int() === 0) {
          unavailable++;
          return '';
        }
        const live = htmlUnescape(data.get('rtmp_live').str());
        return live.length > 0 ? `${data.get('rtmp_url').str()}/${live}` : '';
      } catch (e) {
        return '';
      }
    }));
    const urls: string[] = signed.filter((u: string) => u.length > 0);
    if (urls.length === 0 && unavailable > 0) {
      throw new Error('斗鱼直播流暂不可用，请稍后刷新');
    }
    return new PlayUrls(urls, { 'user-agent': UA_PC, 'referer': 'https://www.douyu.com/' });
  }

  async getLiveStatus(roomId: string): Promise<boolean> {
    const room = await this.getBetard(roomId);
    return room.get('show_status').int() === 1 && room.get('videoLoop').int() !== 1;
  }

  static parseHot(hn: string): number {
    const n = parseFloat(hn.replace('万', ''));
    if (isNaN(n)) {
      return 0;
    }
    return Math.round(hn.indexOf('万') >= 0 ? n * 10000 : n);
  }

  parseRoomUrl(text: string): string {
    let m = text.match(/douyu\.com\/(?:beta\/|topic\/\w+\?rid=)?(\d+)/);
    if (m !== null) {
      return m[1];
    }
    m = text.match(/douyu\.com\/.*[?&]rid=(\d+)/);
    return m !== null ? m[1] : '';
  }
}
