import assert from 'node:assert/strict';
import { BiliQrLogin, biliAuthCookies } from '../../entry/src/main/ets/core/sites/BiliQrLogin';
import { HttpRequest, HttpResponse, HttpTransport, Platform } from '../../entry/src/main/ets/core/common/Transport';
import { BiliSite } from '../../entry/src/main/ets/core/sites/BiliSite';
import { LiveRoomDetail, PlayQuality } from '../../entry/src/main/ets/core/model/Models';

function response(body: object, cookies: string[] = [], status = 200): HttpResponse {
  const out = new HttpResponse();
  out.status = status;
  out.text = JSON.stringify(body);
  out.setCookies = cookies;
  return out;
}

const outer = (data: object, code = 0): object => ({ code, data });
const poll = (code: number, url = ''): object => outer({ code, url });
const nav = (isLogin: boolean): object => outer({ isLogin, mid: isLogin ? 12345 : 0, uname: 'test account' });
const rawCookies = [
  'SESSDATA=session123; Path=/; Secure; HttpOnly; Expires=Wed, 21 Oct 2030 07:28:00 GMT',
  'bili_jct=csrf123; Path=/; Secure',
  'DedeUserID=12345; Path=/; HttpOnly'
];
const expectedCookie = 'SESSDATA=session123; bili_jct=csrf123; DedeUserID=12345';
assert.equal(biliAuthCookies(rawCookies), expectedCookie);
assert.equal(biliAuthCookies([rawCookies.join(', ')]), expectedCookie);
assert.equal(biliAuthCookies([expectedCookie]), expectedCookie);
assert.equal(biliAuthCookies(['Path=/; HttpOnly; expires=Wed, 21 Oct 2030 07:28:00 GMT']), '');
// Lines are parsed separately: CR/LF never reaches the Cookie header, injected header names are ignored.
const split = biliAuthCookies(['SESSDATA=ok\r\nX-Injected: yes; DedeUserID=12345']);
assert.equal(split, 'SESSDATA=ok; DedeUserID=12345');
assert.ok(!/[\r\n]/.test(split));
// HarmonyOS http exposes `cookies` in Netscape cookie-file format.
const netscape = [
  '# Netscape HTTP Cookie File',
  '#HttpOnly_.bilibili.com\tTRUE\t/\tTRUE\t1905000000\tSESSDATA\tsession123',
  '.bilibili.com\tTRUE\t/\tFALSE\t1905000000\tbili_jct\tcsrf123',
  '.bilibili.com\tTRUE\t/\tFALSE\t1905000000\tDedeUserID\t12345',
  '.bilibili.com\tTRUE\t/\tFALSE\t1905000000\tbuvid3\tignored'
].join('\n');
assert.equal(biliAuthCookies([netscape]), expectedCookie);

class MockHttp implements HttpTransport {
  replies: HttpResponse[] = [];
  requests: HttpRequest[] = [];
  async send(req: HttpRequest): Promise<HttpResponse> {
    this.requests.push(req);
    const answer = this.replies.shift();
    assert.ok(answer, 'unexpected request');
    return answer;
  }
}
const mock = new MockHttp();
Platform.http = mock;
const login = new BiliQrLogin();

mock.replies.push(response(outer({ url: 'https://account.bilibili.com/h5/account-h5/auth/scan-web?navhide=1', qrcode_key: 'key123' })));
const ticket = await login.begin();
assert.equal(ticket.url, 'https://account.bilibili.com/h5/account-h5/auth/scan-web?navhide=1');
assert.equal(ticket.key, 'key123');
assert.ok(ticket.expiresAt > Date.now());
mock.replies.push(response(poll(86101)));
assert.equal((await login.poll(ticket.key)).state, 'pending');
mock.replies.push(response(poll(86090)));
assert.equal((await login.poll(ticket.key)).state, 'scanned');
mock.replies.push(response(poll(86038)));
assert.equal((await login.poll(ticket.key)).state, 'expired');

mock.replies.push(response(poll(0), rawCookies), response(nav(true)));
const direct = await login.poll(ticket.key);
assert.equal(direct.state, 'success');
assert.equal(direct.account?.cookie, expectedCookie);
assert.equal(direct.account?.userId, 12345);
assert.equal(direct.account?.name, 'test account');
assert.equal(mock.requests.at(-1)?.headers['cookie'], expectedCookie);

// The success URL itself carries the session fields; no follow-up request is needed.
const fieldUrl = 'https://passport.biligame.com/x/passport-login/web/crossDomain?DedeUserID=12345' +
  '&DedeUserID__ckMd5=md5&Expires=1&SESSDATA=abc%2C1905000000%2Cxyz*b1&bili_jct=csrf123&gourl=https%3A%2F%2Fwww.bilibili.com';
mock.replies.push(response(poll(0, fieldUrl)), response(nav(true)));
assert.equal((await login.poll(ticket.key)).account?.cookie,
  'SESSDATA=abc%2C1905000000%2Cxyz*b1; bili_jct=csrf123; DedeUserID=12345; DedeUserID__ckMd5=md5');
assert.equal(mock.requests.at(-1)?.url.startsWith('https://api.bilibili.com/x/web-interface/nav'), true);
// A query on an untrusted host is never treated as credentials.
mock.replies.push(response(poll(0, 'https://evil.example/?SESSDATA=x&DedeUserID=12345')));
await assert.rejects(login.poll(ticket.key), /凭据未返回/);

const ssoUrl = 'https://passport.biligame.com/crossDomain?ticket=private123';
mock.replies.push(response(poll(0, ssoUrl)), response(outer({}), rawCookies), response(nav(true)));
assert.equal((await login.poll(ticket.key)).state, 'success');
assert.equal(mock.requests.at(-2)?.url, ssoUrl);
assert.equal(mock.requests.at(-2)?.headers['cookie'], undefined);
mock.replies.push(response(poll(0, ssoUrl), [rawCookies[0]]), response(outer({}), rawCookies.slice(1)),
  response(nav(true)));
assert.equal((await login.poll(ticket.key)).account?.cookie, expectedCookie);

mock.replies.push(response(poll(0, 'https://passport.biligame.com.evil.test/crossDomain')));
await assert.rejects(login.poll(ticket.key), /凭据未返回/);
mock.replies.push(response(poll(0), rawCookies), response(nav(false)));
await assert.rejects(login.poll(ticket.key), /登录已失效/);
mock.replies.push(response(poll(0), rawCookies.map((c) => c.replace('DedeUserID=12345', 'DedeUserID=99999'))),
  response(nav(true)));
await assert.rejects(login.poll(ticket.key), /登录已失效/);
mock.replies.push(response(poll(0, ssoUrl)));
mock.replies.push(response(outer({}, -1), [], 503));
await assert.rejects(login.poll(ticket.key), (error: Error) => !error.message.includes('private123'));
assert.equal(mock.requests.at(-2)?.headers['cookie'], undefined);

mock.replies.push(response(nav(true)));
assert.equal(await login.check(expectedCookie), true);
mock.replies.push(response({ code: -101, data: { isLogin: false } }));
assert.equal(await login.check(expectedCookie), false);
mock.replies.push(response(nav(false)));
assert.equal(await login.check(expectedCookie), false);
mock.replies.push(response({ code: -412 }));
assert.equal(await login.check(expectedCookie), null);
mock.replies.push(response({}, [], 503));
assert.equal(await login.check(expectedCookie), null);
assert.equal(await login.check('bili_jct=only'), false);

const site = new BiliSite();
site.setCookie('SESSDATA=session123; DedeUserID=12345; buvid3=buvid; buvid4=buvid4', 12345);
const detail = new LiveRoomDetail();
detail.roomId = '789';
mock.replies.push(response(outer({ playurl_info: { playurl: { stream: [
  { protocol_name: 'http_stream', format: [{ codec: [{ current_qn: 2000, base_url: '/test.flv',
    url_info: [{ host: 'https://a.example/', extra: '?token=one' },
      { host: 'https://mcdn.example/', extra: '?token=two' }] }] }] },
  { protocol_name: 'http_hls', format: [{ codec: [{ current_qn: 10000, base_url: '/test.m3u8',
    url_info: [{ host: 'https://b.example/', extra: '?token=three' }] }] }] }
] } } })));
const stream = await site.getPlayUrls(detail, new PlayQuality('原画', 10000, 10000));
assert.equal(stream.urls.length, 3);
assert.deepEqual(stream.qualityIds, [2000, 2000, 10000]);
assert.equal(mock.requests.at(-1)?.headers['cookie']?.includes('SESSDATA='), true);
const noChatSite = new BiliSite();
noChatSite.setCookie('SESSDATA=session123; DedeUserID=12345; buvid3=buvid', 12345);
const imgUrl = `https://example.test/${'a'.repeat(32)}.png`;
const subUrl = `https://example.test/${'b'.repeat(32)}.png`;
mock.replies.push(response(outer({ wbi_img: { img_url: imgUrl, sub_url: subUrl } })),
  response(outer({ room_info: { room_id: 789, title: 'fixture room', live_status: 1 },
    anchor_info: { base_info: { uname: 'fixture anchor' } } })),
  response(outer({}, -412)));
const noChat = await noChatSite.getRoomDetail('789');
assert.equal(noChat.status, true, 'video detail survives unavailable danmaku server');
assert.equal((noChat.danmakuArgs as { token: string }).token, '');
console.log('Bilibili QR login, stream quality and optional danmaku failure: synthetic tests passed');
