// End-to-end verification of the protocol layer against live endpoints.
// Usage: npm run verify [-- site --room=12345 --danmaku-seconds=20]
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { Inflate } from '../../entry/src/main/ets/core/common/Inflate';
import { installNodePlatform } from './node-platform';
import { Sites, LinkParser } from '../../entry/src/main/ets/core/sites/Sites';
import { HuyaSite } from '../../entry/src/main/ets/core/sites/HuyaSite';
import { Query, stripTags } from '../../entry/src/main/ets/core/common/Http';
import { LiveSite } from '../../entry/src/main/ets/core/sites/LiveSite';
import { Md5, Base64, Utf8 } from '../../entry/src/main/ets/core/common/Bytes';
import { TarsInputStream, TarsOutputStream } from '../../entry/src/main/ets/core/tars/Tars';
import { LiveMessageType } from '../../entry/src/main/ets/core/model/Models';

installNodePlatform();

const argv = process.argv.slice(2);
const only = argv.find((a) => !a.startsWith('--'));
const chosenRoomId = (argv.find((a) => a.startsWith('--room=')) ?? '').split('=')[1];
const danmakuSeconds = Number((argv.find((a) => a.startsWith('--danmaku-seconds=')) ?? '=15').split('=')[1]);

let failures = 0;
function ok(name: string, cond: boolean, detail = ''): void {
  console.log(`${cond ? '  ✓' : '  ✗'} ${name}${detail ? '  — ' + detail : ''}`);
  if (!cond) failures++;
}
async function step<T>(name: string, fn: () => Promise<T>): Promise<T | undefined> {
  try {
    return await fn();
  } catch (e) {
    ok(name, false, String((e as Error)?.stack ?? e).split('\n').slice(0, 3).join(' | '));
    return undefined;
  }
}

function unitTests(): void {
  console.log('\n[unit] bytes / tars');
  for (const s of ['', 'abc', 'The quick brown fox', '斗鱼直播 🎉', 'x'.repeat(200)]) {
    ok(`md5(${JSON.stringify(s.slice(0, 16))})`, Md5.hex(s) === crypto.createHash('md5').update(s).digest('hex'));
    ok(`utf8 roundtrip ${JSON.stringify(s.slice(0, 10))}`, Utf8.decode(Utf8.encode(s)) === s);
    ok(`base64 ${JSON.stringify(s.slice(0, 10))}`, Base64.encode(Utf8.encode(s)) === Buffer.from(s).toString('base64'));
  }
  const os = new TarsOutputStream();
  os.writeInt(0, 0); os.writeInt(-5, 1); os.writeInt(300, 2); os.writeInt(70000, 3); os.writeInt(1712345678901, 4);
  os.writeString('hello', 5); os.writeString('y'.repeat(300), 6); os.writeBytes(new Uint8Array([1, 2, 3]), 7);
  const is = new TarsInputStream(os.toBytes());
  ok('tars ints', is.readInt(0) === 0 && is.readInt(1) === -5 && is.readInt(2) === 300 && is.readInt(3) === 70000 &&
    is.readInt(4) === 1712345678901);
  ok('tars strings', is.readString(5) === 'hello' && is.readString(6).length === 300);
  ok('tars bytes', is.readBytes(7).join(',') === '1,2,3');
  for (const n of [0, 10, 1000, 70000]) {
    const src = Buffer.from(Array.from({ length: n }, (_, i) => (i * 7 + (i >> 5)) % 251));
    const txt = Buffer.from(JSON.stringify({ cmd: 'DANMU_MSG', info: 'x'.repeat(n % 500) }).repeat(1 + n % 7));
    for (const [name, buf] of [['bin', src], ['txt', txt]] as const) {
      for (const level of [0, 6, 9]) {
        const out = Inflate.zlib(new Uint8Array(zlib.deflateSync(buf, { level })));
        ok(`inflate ${name} n=${n} level=${level}`, Buffer.from(out).equals(buf));
      }
    }
  }
  const refs = LinkParser.parse('https://www.huya.com/kaerlol');
  ok('link huya', refs.length === 1 && refs[0].siteId === 'huya' && refs[0].roomId === 'kaerlol');
  const d = LinkParser.parse('https://www.douyu.com/9999?dyshid=1');
  ok('link douyu', d.length === 1 && d[0].roomId === '9999');
  const b = LinkParser.parse('https://live.bilibili.com/h5/21452505?from=x');
  ok('link bili', b.length === 1 && b[0].siteId === 'bilibili' && b[0].roomId === '21452505');
  ok('link number', LinkParser.parse(' 12345 ').length === 3);
  ok('html title entities', stripTags('<em>鱼&amp;猫</em>') === '鱼&猫');
  ok('form query plus', Query.parse('name=a+b').name === 'a b');
  const anti = HuyaSite.buildAntiCode('stream', 1, 'fm=cHJlZml4XyA+&wsTime=123&ctype=huya_pc_exe');
  ok('huya fm literal plus', anti.includes('fm=cHJlZml4XyA%2B'));
  let invalidSiteRejected = false;
  try {
    Sites.of('not-a-platform');
  } catch (e) {
    invalidSiteRejected = true;
  }
  ok('unknown platform rejected', invalidSiteRejected);
}

async function verifySite(site: LiveSite): Promise<void> {
  console.log(`\n[${site.id}] ${site.name}`);
  const cats = await step('categories', () => site.getCategories());
  if (cats) {
    const subs = cats.reduce((n, c) => n + c.children.length, 0);
    ok('categories', cats.length > 0 && subs > 0, `${cats.length} groups / ${subs} subs, e.g. ${cats[0]?.children[0]?.name}`);
    const sub = cats.find((c) => c.children.length > 0)?.children[0];
    if (sub) {
      const cr = await step('category rooms', () => site.getCategoryRooms(sub, 1));
      if (cr) ok('category rooms', cr.items.length > 0, `${sub.name}: ${cr.items.length} rooms, hasMore=${cr.hasMore}`);
    }
  }
  const rec = await step('recommend', () => site.getRecommendRooms(1));
  if (!rec) return;
  ok('recommend', rec.items.length > 0, `${rec.items.length} rooms; first: ${rec.items[0]?.userName} · ${rec.items[0]?.title}`);
  const first = rec.items[0];
  ok('recommend item fields', !!first && first.roomId.length > 0 && first.cover.startsWith('https://'),
    `cover=${first?.cover.slice(0, 60)} avatar=${first?.avatar.slice(0, 50)} online=${first?.online} area=${first?.area}`);
  const rec2 = await step('recommend p2', () => site.getRecommendRooms(2));
  if (rec2) ok('recommend page 2', rec2.items.length > 0 && rec2.items[0].roomId !== first.roomId, `${rec2.items.length} rooms`);

  const kw = first.userName.slice(0, 4) || '英雄联盟';
  const sr = await step('search rooms', () => site.searchRooms(kw, 1));
  if (sr) ok('search rooms', Array.isArray(sr.items) && sr.items.every((item) => item.roomId.length > 0),
    `"${kw}" → ${sr.items.length} rooms (empty is valid)`);
  const sa = await step('search anchors', () => site.searchAnchors(kw, 1));
  if (sa) ok('search anchors', Array.isArray(sa.items) &&
    sa.items.every((item) => item.roomId.length > 0),
    `"${kw}" → ${sa.items.length} anchors (empty is valid)`);

  const detail = await step('room detail', () => site.getRoomDetail(chosenRoomId || first.roomId));
  if (!detail) return;
  ok('room detail', detail.title.length > 0 && detail.userName.length > 0,
    `${detail.userName} · ${detail.title} · live=${detail.status} · online=${detail.online} · area=${detail.area} · start=${detail.startTime}`);
  const live = await step('live status', () => site.getLiveStatus(detail.roomId));
  ok('live status', live === true, String(live));

  const qs = await step('qualities', () => site.getPlayQualities(detail));
  if (!qs) return;
  ok('qualities', qs.length > 0, qs.map((q) => `${q.name}(${q.sort})`).join(', '));
  const best = [...qs].sort((a, b) => b.sort - a.sort)[0];
  const urls = await step('play urls', () => site.getPlayUrls(detail, best));
  if (!urls) return;
  ok('play urls', urls.urls.length > 0, `${urls.urls.length} lines; signed addresses redacted`);
  if (urls.urls.length > 0) {
    const probe = await step('stream probe', async () => {
      const ctrl = new AbortController();
      const r = await fetch(urls.urls[0], { headers: urls.headers, signal: ctrl.signal });
      const reader = r.body!.getReader();
      const chunk = await reader.read();
      ctrl.abort();
      return { status: r.status, head: Buffer.from(chunk.value ?? []).subarray(0, 3).toString('latin1'), type: r.headers.get('content-type') };
    });
    if (probe) ok('stream reachable', probe.status === 200 && (probe.head === 'FLV' || probe.head.startsWith('#EX')),
      `status=${probe.status} magic=${JSON.stringify(probe.head)} type=${probe.type}`);
  }

  await new Promise<void>((resolve) => {
    const dm = site.createDanmaku();
    let chats = 0; let online = 0; let sc = 0; let ready = false;
    dm.onReady = () => { ready = true; };
    dm.onMessage = (m) => {
      if (m.type === LiveMessageType.Chat) chats++;
      else if (m.type === LiveMessageType.Online) online = m.online;
      else sc++;
    };
    dm.start(detail.danmakuArgs);
    setTimeout(() => {
      dm.stop();
      ok('danmaku connection', ready, `socket opened during ${danmakuSeconds}s probe`);
      console.log(`  • chat sample: ${chats} messages, online=${online}, sc=${sc}` +
        (chats === 0 ? ' (quiet window; not proof of disconnect)' : ''));
      resolve();
    }, danmakuSeconds * 1000);
  });
}

unitTests();
for (const s of Sites.all) {
  if (only && s.id !== only) continue;
  await verifySite(s);
}
console.log(`\n${failures === 0 ? 'ALL PASSED' : failures + ' FAILURE(S)'}`);
process.exit(failures === 0 ? 0 : 1);
