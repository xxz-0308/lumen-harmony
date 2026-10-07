import { Http, UA_PC } from '../common/Http';
import { HttpResponse, Platform } from '../common/Transport';
import { JNode } from '../common/Json';

const GENERATE = 'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';
const POLL = 'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';
const NAV = 'https://api.bilibili.com/x/web-interface/nav';
const AUTH_COOKIES: string[] = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5'];
const HEADERS: Record<string, string> = { 'user-agent': UA_PC, 'referer': 'https://www.bilibili.com/' };

export class BiliQrTicket {
  url: string = '';
  key: string = '';
  expiresAt: number = 0;
}

export class BiliAccount {
  cookie: string = '';
  userId: number = 0;
  name: string = '';
}

export type BiliQrState = 'pending' | 'scanned' | 'expired' | 'success';

export class BiliQrResult {
  state: BiliQrState = 'pending';
  account?: BiliAccount;
}

/** Only cookie name/value pairs are sent back; never forward Set-Cookie attributes as a Cookie header. */
export function biliAuthCookies(fields: string[]): string {
  const values: Record<string, string> = {};
  const put = (name: string, value: string): void => {
    if (AUTH_COOKIES.indexOf(name) >= 0 && value.length > 0 && value.length <= 4096 && !/[\s;,]/.test(value)) {
      values[name] = value;
    }
  };
  for (const field of fields) {
    // Lines are parsed separately, so CR/LF can never reach the outgoing Cookie header.
    for (const line of field.split(/\r?\n/)) {
      // HarmonyOS exposes `cookies` in Netscape cookie-file format:
      // domain \t flag \t path \t secure \t expires \t name \t value
      const cols = line.split('\t');
      if (cols.length >= 7) {
        put(cols[5].trim(), cols[6].trim());
        continue;
      }
      // Set-Cookie fields, coalesced header values, cookie strings, or `name=value` query pairs.
      const pairs = line.match(/(?:^|[,;&?])\s*(SESSDATA|bili_jct|DedeUserID|DedeUserID__ckMd5)=([^;,&\s]+)/g);
      if (!pairs) {
        continue;
      }
      for (const pair of pairs) {
        const eq = pair.indexOf('=');
        put(pair.substring(0, eq).replace(/^[,;&?]\s*/, ''), pair.substring(eq + 1).trim());
      }
    }
  }
  return AUTH_COOKIES.filter((name: string) => values[name] !== undefined)
    .map((name: string) => `${name}=${values[name]}`).join('; ');
}

/** The success URL carries the same session fields as query parameters (raw, still cookie-encoded). */
function urlAuthFields(url: string): string[] {
  if (!/^https:\/\/passport\.(?:biligame|bilibili)\.com\//.test(url)) {
    return [];
  }
  const q = url.indexOf('?');
  return q < 0 ? [] : [url.substring(q).split('#')[0]];
}

function cookieNames(cookie: string): string {
  return AUTH_COOKIES.filter((name: string) => new RegExp(`(?:^|; )${name}=`).test(cookie)).join(',');
}

function cookieFields(response: HttpResponse): string[] {
  const fields = response.setCookies.slice();
  if (response.headers['set-cookie']) {
    fields.push(response.headers['set-cookie']);
  }
  return fields;
}

function hasSession(cookie: string): boolean {
  return /(?:^|;\s*)SESSDATA=/.test(cookie) && /(?:^|;\s*)DedeUserID=/.test(cookie);
}

function parseResponse(response: HttpResponse): JNode {
  const json = JNode.tryParse(response.text);
  const code = json.get('code').int(-1);
  if (!json.isObject || code !== 0) {
    Platform.log(`[bili-auth] response rejected status=${response.status} code=${code}`);
    throw new Error('B站登录服务暂不可用');
  }
  return json.get('data');
}

export class BiliQrLogin {
  async begin(): Promise<BiliQrTicket> {
    const data = parseResponse(await Http.getResponse(GENERATE, undefined, HEADERS));
    const ticket = new BiliQrTicket();
    ticket.url = data.get('url').str();
    ticket.key = data.get('qrcode_key').str();
    // The scan page moved from passport.* to account.bilibili.com; accept only these two hosts.
    if (!/^https:\/\/(?:passport|account)\.bilibili\.com\//.test(ticket.url) || ticket.key.length === 0) {
      throw new Error('B站二维码不可用');
    }
    ticket.expiresAt = Date.now() + 180000;
    return ticket;
  }

  async poll(key: string): Promise<BiliQrResult> {
    if (!key || key.length > 256 || !/^[a-zA-Z0-9_-]+$/.test(key)) {
      throw new Error('B站二维码无效');
    }
    const response = await Http.getResponse(POLL, { 'qrcode_key': key }, HEADERS);
    const data = parseResponse(response);
    const code = data.get('code').int(-1);
    Platform.log(`[bili-auth] poll state code=${code}`);
    const result = new BiliQrResult();
    if (code === 86101 || code === 86090) {
      result.state = code === 86101 ? 'pending' : 'scanned';
      return result;
    }
    if (code === 86038) {
      result.state = 'expired';
      return result;
    }
    if (code !== 0) {
      throw new Error(`B站扫码请求失败（${code}），请稍后重试`);
    }
    const url = data.get('url').str();
    const host = url.match(/^https:\/\/([^/?#]+)/);
    Platform.log(`[bili-auth] success URL host=${host ? host[1] : 'none'}`);
    // Response headers win over the URL copy when both carry a field.
    let fields = urlAuthFields(url).concat(cookieFields(response));
    let cookie = biliAuthCookies(fields);
    Platform.log(`[bili-auth] poll ok: ${response.setCookies.length} cookie fields, found ${cookieNames(cookie) || 'none'}`);
    if (!hasSession(cookie)) {
      // The cross-domain ticket currently issues the session cookies. Never send existing credentials to it.
      if (!/^https:\/\/passport\.biligame\.com(?:\/|\?)/.test(url)) {
        throw new Error('B站登录凭据未返回');
      }
      const ticketResponse = await Http.getResponse(url, undefined, HEADERS);
      fields = fields.concat(cookieFields(ticketResponse));
      cookie = biliAuthCookies(fields);
      Platform.log(`[bili-auth] ticket response status=${ticketResponse.status}, found ${cookieNames(cookie) || 'none'}`);
    }
    if (!hasSession(cookie)) {
      throw new Error('B站登录凭据未返回');
    }
    result.account = await this.verify(cookie);
    result.state = 'success';
    return result;
  }

  /**
   * Checks a restored session. Returns false only when Bilibili definitively reports it logged out
   * (-101 or isLogin=false); network or service errors return null so a flaky start never signs out.
   */
  async check(cookie: string): Promise<boolean | null> {
    if (!hasSession(cookie)) {
      return false;
    }
    let nav: JNode;
    try {
      nav = JNode.tryParse((await Http.getResponse(NAV, undefined,
        { 'user-agent': HEADERS['user-agent'], 'referer': HEADERS['referer'], 'cookie': cookie })).text);
    } catch (e) {
      return null;
    }
    if (!nav.isObject) {
      return null;
    }
    const code = nav.get('code').int(-1);
    if (code === -101) {
      return false;
    }
    if (code !== 0) {
      return null;
    }
    const isLogin = nav.get('data').get('isLogin').value;
    return typeof isLogin === 'boolean' ? isLogin as boolean : null;
  }

  async verify(cookie: string): Promise<BiliAccount> {
    if (!hasSession(cookie)) {
      throw new Error('B站登录凭据不完整');
    }
    const nav = JNode.tryParse((await Http.getResponse(NAV, undefined,
      { 'user-agent': HEADERS['user-agent'], 'referer': HEADERS['referer'], 'cookie': cookie })).text);
    const navCode = nav.get('code').int(-1);
    if (!nav.isObject || navCode !== 0) {
      Platform.log(`[bili-auth] nav rejected code=${navCode}`);
      throw new Error('B站登录已失效');
    }
    const data = nav.get('data');
    const uid = data.get('mid').int();
    const cookieUid = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)(?:;|$)/);
    const matches = cookieUid !== null && Number(cookieUid[1]) === uid;
    Platform.log(`[bili-auth] nav isLogin=${data.get('isLogin').bool()} uidValid=${uid > 0} uidMatch=${matches}`);
    if (!data.get('isLogin').bool() || uid <= 0 || !matches) {
      throw new Error('B站登录已失效');
    }
    const account = new BiliAccount();
    account.cookie = cookie;
    account.userId = uid;
    account.name = data.get('uname').str();
    return account;
  }
}
