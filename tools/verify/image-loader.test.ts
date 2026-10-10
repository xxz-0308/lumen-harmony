import assert from 'node:assert/strict';
import { HttpRequest, HttpResponse, Platform } from '../../entry/src/main/ets/core/common/Transport';
import { ImageLoader } from '../../entry/src/main/ets/util/ImageLoader';
import { imageStats } from './kit-image';

let active = 0;
let peak = 0;
const waiters: (() => void)[] = [];
Platform.http = {
  send: async (_req: HttpRequest): Promise<HttpResponse> => {
    active++;
    peak = Math.max(peak, active);
    await new Promise<void>((resolve) => waiters.push(resolve));
    active--;
    const res = new HttpResponse();
    res.status = 200;
    res.bytes = new Uint8Array([1, 2, 3]);
    return res;
  }
};
const urls = Array.from({ length: 24 }, (_, i) => `https://apic.douyucdn.cn/avatar/${i}.png`);
const tasks = urls.map((url) => ImageLoader.load(url));
assert.equal(peak, 8, 'at most eight manual image requests start concurrently');
const duplicate = ImageLoader.load(urls[0]);
assert.equal(duplicate, tasks[0], 'same URL shares its pending request');
while (waiters.length > 0 || active > 0) {
  const batch = waiters.splice(0);
  for (const done of batch) done();
  await new Promise<void>((resolve) => setTimeout(resolve, 0));
}
const images = await Promise.all(tasks.concat([duplicate]));
assert.equal(images.filter(Boolean).length, 25);
assert.equal(peak, 8);
assert.equal(ImageLoader.cached(urls[0]), images[0]);
let sends = 0, fail = false;
Platform.http = { send: async (req: HttpRequest) => {
  sends++; if (req.url.endsWith('/throw')) throw new Error('fixture HTTP failure');
  const res = new HttpResponse(); res.status = fail ? 503 : 200; res.bytes = new Uint8Array([1]); return res;
} };
for (let i = 24; i < 160; i++) await ImageLoader.load(`https://apic.douyucdn.cn/avatar/${i}.png`);
assert.equal(ImageLoader.cached(urls[1]), images[1]);
assert.equal(await ImageLoader.load(urls[2]), images[2]);
await ImageLoader.load('https://apic.douyucdn.cn/avatar/overflow');
assert.equal(ImageLoader.cached(urls[3]), null, 'both cached() and load() promote recently used images');
assert.equal(ImageLoader.cached(urls[1]), images[1]);assert.equal(ImageLoader.cached(urls[2]), images[2]);
assert.ok(imageStats.pixels.every(pm => !pm.released), 'eviction does not release output held by mounted consumers');
const realNow = Date.now; let now = realNow(); Date.now = () => now;
try {
  fail = true; const before = sends; assert.equal(await ImageLoader.load('fixture/fail'), null);
  assert.equal(await ImageLoader.load('fixture/fail'), null); assert.equal(sends, before + 1);
  now += 30001; fail = false; assert.ok(await ImageLoader.load('fixture/fail'));
  imageStats.failDecode = true; assert.equal(await ImageLoader.load('fixture/decode'), null);
  const decoded = sends; assert.equal(await ImageLoader.load('fixture/decode'), null); assert.equal(sends, decoded);
  now += 30001; assert.ok(await ImageLoader.load('fixture/decode'));
  const drain = await Promise.all([ImageLoader.load('fixture/throw'), ...Array.from({ length: 12 }, (_, i) => ImageLoader.load(`fixture/drain/${i}`))]);
  assert.equal(drain.filter(Boolean).length, 12, 'exceptions do not stall the queue');
  assert.equal(imageStats.sources, imageStats.sourceReleases);
  assert.ok(imageStats.pixels.every(pm => pm.width === 160 && pm.height === 160));
} finally { Date.now = realNow; }
console.log('ImageLoader: concurrency, dedup, true LRU, failure expiry, queue recovery and shared output ownership passed');
