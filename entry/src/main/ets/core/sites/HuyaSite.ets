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
import { Http, httpsUrl, Query, UA_MOBILE } from '../common/Http';
import { JNode } from '../common/Json';
import { Base64, Md5, Utf8 } from '../common/Bytes';
import { TarsInputStream, TarsOutputStream, TarsStruct, TupPacket } from '../tars/Tars';
import { LiveDanmaku } from '../danmaku/LiveDanmaku';
import { HuyaDanmaku, HuyaDanmakuArgs } from '../danmaku/HuyaDanmaku';

const HYSDK_UA = 'HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)';

export class HuyaLine {
  line: string = '';
  cdnType: string = '';
  flvAntiCode: string = '';
  streamName: string = '';
  presenterUid: number = 0;
}

export class HuyaBitRate {
  name: string = '';
  bitRate: number = 0;
}

export class HuyaRoomData {
  lines: HuyaLine[] = [];
  bitRates: HuyaBitRate[] = [];
}

class HuyaQualityData {
  bitRate: number = 0;
  lines: HuyaLine[] = [];
}

class HuyaUserId implements TarsStruct {
  lUid: number = 0;
  sGuid: string = '';
  sToken: string = '';
  sHuYaUA: string = '';
  sCookie: string = '';
  iTokenType: number = 0;
  sDeviceInfo: string = '';
  sQIMEI: string = '';

  writeTo(os: TarsOutputStream): void {
    os.writeInt(this.lUid, 0);
    os.writeString(this.sGuid, 1);
    os.writeString(this.sToken, 2);
    os.writeString(this.sHuYaUA, 3);
    os.writeString(this.sCookie, 4);
    os.writeInt(this.iTokenType, 5);
    os.writeString(this.sDeviceInfo, 6);
    os.writeString(this.sQIMEI, 7);
  }

  readFrom(is: TarsInputStream): void {
    this.lUid = is.readInt(0);
    this.sGuid = is.readString(1);
  }
}

class GetCdnTokenExReq implements TarsStruct {
  sFlvUrl: string = '';
  sStreamName: string = '';
  iLoopTime: number = 0;
  tId: HuyaUserId = new HuyaUserId();
  iAppId: number = 66;

  writeTo(os: TarsOutputStream): void {
    os.writeString(this.sFlvUrl, 0);
    os.writeString(this.sStreamName, 1);
    os.writeInt(this.iLoopTime, 2);
    os.writeStruct(this.tId, 3);
    os.writeInt(this.iAppId, 4);
  }

  readFrom(is: TarsInputStream): void {
  }
}

class GetCdnTokenExResp implements TarsStruct {
  sFlvToken: string = '';
  iExpireTime: number = 0;

  writeTo(os: TarsOutputStream): void {
  }

  readFrom(is: TarsInputStream): void {
    this.sFlvToken = is.readString(0);
    this.iExpireTime = is.readInt(1);
  }
}

export class HuyaSite extends LiveSite {
  readonly id: SiteId = 'huya';
  readonly name: string = '虎牙直播';
  readonly shortName: string = '虎牙';

  createDanmaku(): LiveDanmaku {
    return new HuyaDanmaku();
  }

  async getCategories(): Promise<LiveCategory[]> {
    const roots: string[][] = [['1', '网游'], ['2', '单机'], ['8', '娱乐'], ['3', '手游']];
    const tasks: Promise<LiveCategory>[] = roots.map(async (r: string[]): Promise<LiveCategory> => {
      const cat = new LiveCategory();
      cat.id = r[0];
      cat.name = r[1];
      cat.children = await this.getSubCategories(r[0]);
      return cat;
    });
    return Promise.all(tasks);
  }

  private async getSubCategories(id: string): Promise<LiveSubCategory[]> {
    const res = await Http.getJson('https://live.cdn.huya.com/liveconfig/game/bussLive', { 'bussType': id });
    const subs: LiveSubCategory[] = [];
    for (const item of res.get('data').list()) {
      const g = item.get('gid');
      const gid = g.isObject ? g.get('value').str().split(',')[0] : String(g.int());
      const sub = new LiveSubCategory();
      sub.siteId = 'huya';
      sub.id = gid;
      sub.name = item.get('gameFullName').str();
      sub.parentId = id;
      sub.pic = `https://huyaimg.msstatic.com/cdnimage/game/${gid}-MS.jpg`;
      subs.push(sub);
    }
    return subs;
  }

  private parseListRooms(res: JNode): RoomPage {
    const data = res.get('data');
    const items: LiveRoomItem[] = [];
    for (const it of data.get('datas').list()) {
      let cover = it.get('screenshot').str();
      if (cover.indexOf('?') < 0) {
        cover += '?x-oss-process=style/w338_h190&';
      }
      let title = it.get('introduction').str();
      if (title.length === 0) {
        title = it.get('roomName').str();
      }
      const room = LiveRoomItem.of('huya', it.get('profileRoom').str(), title, httpsUrl(cover),
        it.get('nick').str(), it.get('totalCount').num());
      room.avatar = httpsUrl(it.get('avatar180').str());
      room.area = it.get('gameFullName').str();
      items.push(room);
    }
    return new RoomPage(items, data.get('page').num() < data.get('totalPage').num());
  }

  async getCategoryRooms(category: LiveSubCategory, page: number): Promise<RoomPage> {
    const res = await Http.getText('https://www.huya.com/cache.php', {
      'm': 'LiveList', 'do': 'getLiveListByPage', 'tagAll': '0', 'gameId': category.id, 'page': String(page)
    });
    return this.parseListRooms(JNode.parse(res));
  }

  async getRecommendRooms(page: number): Promise<RoomPage> {
    const res = await Http.getText('https://www.huya.com/cache.php', {
      'm': 'LiveList', 'do': 'getLiveListByPage', 'tagAll': '0', 'page': String(page)
    });
    return this.parseListRooms(JNode.parse(res));
  }

  async searchRooms(keyword: string, page: number): Promise<RoomPage> {
    const res = JNode.parse(await Http.getText('https://search.cdn.huya.com/', {
      'm': 'Search', 'do': 'getSearchContent', 'q': keyword, 'uid': '0', 'v': '4', 'typ': '-5',
      'livestate': '0', 'rows': '20', 'start': String((page - 1) * 20)
    }));
    const block = res.path('response.3');
    const items: LiveRoomItem[] = [];
    for (const it of block.get('docs').list()) {
      let cover = it.get('game_screenshot').str();
      if (cover.indexOf('?') < 0) {
        cover += '?x-oss-process=style/w338_h190&';
      }
      let title = it.get('game_introduction').str();
      if (title.length === 0) {
        title = it.get('game_roomName').str();
      }
      const room = LiveRoomItem.of('huya', it.get('room_id').str(), title, httpsUrl(cover),
        it.get('game_nick').str(), it.get('game_total_count').num());
      room.avatar = httpsUrl(it.get('game_imgUrl').str());
      room.area = it.get('gameName').str();
      items.push(room);
    }
    return new RoomPage(items, block.get('numFound').num() > page * 20);
  }

  async searchAnchors(keyword: string, page: number): Promise<AnchorPage> {
    const res = JNode.parse(await Http.getText('https://search.cdn.huya.com/', {
      'm': 'Search', 'do': 'getSearchContent', 'q': keyword, 'uid': '0', 'v': '1', 'typ': '-5',
      'livestate': '0', 'rows': '20', 'start': String((page - 1) * 20)
    }));
    const block = res.path('response.1');
    const items: LiveAnchorItem[] = [];
    for (const it of block.get('docs').list()) {
      const a = new LiveAnchorItem();
      a.siteId = 'huya';
      a.roomId = it.get('room_id').str();
      a.avatar = httpsUrl(it.get('game_avatarUrl180').str());
      a.userName = it.get('game_nick').str();
      a.liveStatus = it.get('gameLiveOn').bool();
      items.push(a);
    }
    return new AnchorPage(items, block.get('numFound').num() > page * 20);
  }

  private async getRoomInfo(roomId: string): Promise<JNode> {
    const html = await Http.getText(`https://m.huya.com/${roomId}`, undefined, { 'user-agent': UA_MOBILE });
    const m = html.match(/window\.HNF_GLOBAL_INIT\s*=\s*(\{[\s\S]*?\})\s*<\/script>/);
    if (m === null) {
      throw new Error('虎牙房间信息解析失败');
    }
    const jsonText = m[1].replace(/function\s*\w*\s*\([^)]*\)\s*\{[\s\S]*?\}/g, '""');
    return JNode.parse(jsonText);
  }

  private static channelIds(info: JNode): number[] {
    const text = JSON.stringify(info.value);
    const top = text.match(/"lChannelId":(\d+)/);
    const sub = text.match(/"lSubChannelId":(\d+)/);
    return [top ? Number(top[1]) : 0, sub ? Number(sub[1]) : 0];
  }

  async getRoomDetail(roomId: string): Promise<LiveRoomDetail> {
    const info = await this.getRoomInfo(roomId);
    const roomInfo = info.get('roomInfo');
    const liveInfo = roomInfo.get('tLiveInfo');
    const profile = roomInfo.get('tProfileInfo');
    const ids = HuyaSite.channelIds(info);
    const topSid = ids[0];
    const subSid = ids[1];

    let title = liveInfo.get('sIntroduction').str();
    if (title.length === 0) {
      title = liveInfo.get('sRoomName').str();
    }

    const data = new HuyaRoomData();
    const presenterUid = topSid;
    for (const s of liveInfo.path('tLiveStreamInfo.vStreamInfo.value').list()) {
      const flv = s.get('sFlvUrl').str();
      if (flv.length === 0) {
        continue;
      }
      const line = new HuyaLine();
      line.line = httpsUrl(flv);
      line.cdnType = s.get('sCdnType').str();
      line.flvAntiCode = s.get('sFlvAntiCode').str();
      line.streamName = s.get('sStreamName').str();
      line.presenterUid = presenterUid;
      data.lines.push(line);
    }
    for (const b of liveInfo.path('tLiveStreamInfo.vBitRateInfo.value').list()) {
      const name = b.get('sDisplayName').str();
      if (name.indexOf('HDR') >= 0) {
        continue;
      }
      const br = new HuyaBitRate();
      br.name = name;
      br.bitRate = b.get('iBitRate').int();
      data.bitRates.push(br);
    }

    const d = new LiveRoomDetail();
    d.siteId = 'huya';
    d.roomId = liveInfo.get('lProfileRoom').str(roomId);
    d.title = title;
    d.cover = httpsUrl(liveInfo.get('sScreenshot').str());
    d.userName = profile.get('sNick').str();
    d.userAvatar = httpsUrl(profile.get('sAvatar180').str());
    d.online = liveInfo.get('lTotalCount').num();
    d.introduction = liveInfo.get('sIntroduction').str();
    d.notice = info.get('welcomeText').str();
    d.status = roomInfo.get('eLiveStatus').int() === 2;
    d.area = liveInfo.get('sGameFullName').str();
    d.startTime = liveInfo.get('iStartTime').int();
    d.url = `https://www.huya.com/${roomId}`;
    d.data = data;
    const args = new HuyaDanmakuArgs();
    args.ayyuid = liveInfo.get('lYyid').num();
    args.topSid = topSid;
    args.subSid = subSid;
    d.danmakuArgs = args;
    return d;
  }

  async getPlayQualities(detail: LiveRoomDetail): Promise<PlayQuality[]> {
    const data = detail.data as HuyaRoomData;
    let rates = data.bitRates;
    if (rates.length === 0) {
      const a = new HuyaBitRate();
      a.name = '原画';
      a.bitRate = 0;
      const b = new HuyaBitRate();
      b.name = '高清';
      b.bitRate = 2000;
      rates = [a, b];
    }
    const out: PlayQuality[] = [];
    for (const r of rates) {
      const qd = new HuyaQualityData();
      qd.bitRate = r.bitRate;
      qd.lines = data.lines;
      // bitRate 0 is the source ("原画") stream and should sort first.
      out.push(new PlayQuality(r.name, r.bitRate === 0 ? 1e9 : r.bitRate, qd));
    }
    return out;
  }

  async getPlayUrls(detail: LiveRoomDetail, quality: PlayQuality): Promise<PlayUrls> {
    const qd = quality.data as HuyaQualityData;
    const urls: string[] = [];
    for (const line of qd.lines) {
      try {
        urls.push(await this.buildPlayUrl(line, qd.bitRate));
      } catch (e) {
        // a failing CDN token should not hide the other lines
      }
    }
    return new PlayUrls(urls, { 'user-agent': HYSDK_UA });
  }

  private async buildPlayUrl(line: HuyaLine, bitRate: number): Promise<string> {
    let anti = await this.getCdnToken(line.streamName);
    if (anti.length === 0) {
      anti = line.flvAntiCode;
    }
    anti = HuyaSite.buildAntiCode(line.streamName, line.presenterUid, anti);
    let url = `${line.line}/${line.streamName}.flv?${anti}&codec=264`;
    if (bitRate > 0) {
      url += `&ratio=${bitRate}`;
    }
    return url;
  }

  private async getCdnToken(stream: string): Promise<string> {
    const req = new GetCdnTokenExReq();
    req.sStreamName = stream;
    req.tId.sHuYaUA = 'pc_exe&7060000&official';
    const body = TupPacket.encode('liveui', 'getCdnTokenInfoEx', 'tReq', req);
    const bytes = await Http.postBytes('http://wup.huya.com', body, {
      'content-type': 'application/x-wup',
      'origin': 'https://m.huya.com/',
      'referer': 'https://m.huya.com/',
      'user-agent': HYSDK_UA
    });
    const values = TupPacket.decode(bytes);
    return TupPacket.readValue(values, 'tRsp', new GetCdnTokenExResp()).sFlvToken;
  }

  /** rotl64 as in the reference: rotate the low 32 bits left by 8, keep the high part. */
  static rotl64(t: number): number {
    const low = t % 4294967296;
    const high = t - low;
    const rotated = (((low << 8) | (low >>> 24)) >>> 0);
    return high + rotated;
  }

  static buildAntiCode(stream: string, presenterUid: number, antiCode: string): string {
    const q = Query.parse(antiCode);
    // Huya's fm is base64 rather than form text: a literal '+' is data, not a space.
    const rawFm = antiCode.match(/(?:^|&)fm=([^&]*)/);
    if (rawFm !== null) {
      q['fm'] = Query.safeDecode(rawFm[1]);
    }
    if (q['fm'] === undefined) {
      return antiCode;
    }
    const ctype = q['ctype'] ?? 'huya_pc_exe';
    const platformId = Number(q['t'] ?? '0');
    const isWap = platformId === 103;
    const now = Date.now();
    const seqId = presenterUid + now;
    const secretHash = Md5.hex(`${seqId}|${ctype}|${platformId}`);
    const convertUid = HuyaSite.rotl64(presenterUid);
    const calcUid = isWap ? presenterUid : convertUid;
    const fm = q['fm'];
    const secretPrefix = Utf8.decode(Base64.decode(fm)).split('_')[0];
    const wsTime = q['wsTime'] ?? '';
    const wsSecret = Md5.hex(`${secretPrefix}_${calcUid}_${stream}_${secretHash}_${wsTime}`);
    const parts: string[] = [
      `wsSecret=${wsSecret}`,
      `wsTime=${wsTime}`,
      `seqid=${seqId}`,
      `ctype=${ctype}`,
      'ver=1',
      `fs=${q['fs'] ?? ''}`,
      `fm=${encodeURIComponent(fm)}`,
      `t=${platformId}`
    ];
    if (isWap) {
      const ct = Math.floor((parseInt(wsTime, 16) + Math.random()) * 1000);
      const uuid = Math.floor(((ct % 1e10) + Math.random()) * 1e3 % 0xffffffff);
      parts.push(`uid=${presenterUid}`, `uuid=${uuid}`);
    } else {
      parts.push(`u=${convertUid}`);
    }
    return parts.join('&');
  }

  async getLiveStatus(roomId: string): Promise<boolean> {
    const info = await this.getRoomInfo(roomId);
    return info.path('roomInfo.eLiveStatus').int() === 2;
  }

  parseRoomUrl(text: string): string {
    const m = text.match(/huya\.com\/([A-Za-z0-9_\-]+)/);
    if (m === null) {
      return '';
    }
    const id = m[1];
    const reserved = ['g', 'l', 'video', 'search', 'cache', 'e', 'myfollow'];
    return reserved.indexOf(id) >= 0 ? '' : id;
  }
}
