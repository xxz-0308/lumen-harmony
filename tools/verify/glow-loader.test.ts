import assert from 'node:assert/strict';
import { HttpRequest, HttpResponse, Platform } from '../../entry/src/main/ets/core/common/Transport';
import { GlowLoader } from '../../entry/src/main/ets/util/GlowLoader';
import { imageStats } from './kit-image';
import { glowStats } from './kit-glow-effect';

let active = 0, peak = 0;
const waiters: (() => void)[] = [];
Platform.http = { send: async () => {
  active++; peak = Math.max(peak, active);
  await new Promise<void>(resolve => waiters.push(resolve)); active--;
  const res = new HttpResponse(); res.status = 200; res.bytes = new Uint8Array([1]); return res;
} };
const urls = Array.from({ length: 9 }, (_, i) => `fixture/glow/${i}`);
const tasks = urls.map(url => GlowLoader.load(url));
assert.equal(peak, 2); assert.equal(GlowLoader.load(urls[0]), tasks[0]);
assert.equal(GlowLoader.load(urls[5]), tasks[5], 'queued URLs also share pending work');
while (waiters.length || active) {
  for (const done of waiters.splice(0)) done();
  await new Promise<void>(resolve => setTimeout(resolve, 0));
}
const images = await Promise.all(tasks); assert.ok(images.every(Boolean)); assert.equal(peak, 2);
let sends = 0, fail = false;
Platform.http = { send: async (req: HttpRequest) => {
  sends++; if (req.url.endsWith('/throw')) throw new Error('fixture HTTP failure');
  const res = new HttpResponse(); res.status = fail ? 503 : 200; res.bytes = new Uint8Array([1]); return res;
} };
for (let i = 9; i < 24; i++) await GlowLoader.load(`fixture/glow/${i}`);
assert.equal(GlowLoader.cached(urls[0]), images[0]); assert.equal(await GlowLoader.load(urls[1]), images[1]);
await GlowLoader.load('fixture/overflow');
assert.equal(GlowLoader.cached(urls[2]), null); assert.equal(GlowLoader.cached(urls[0]), images[0]);
assert.equal(GlowLoader.cached(urls[1]), images[1]);
assert.ok(glowStats.pixels.every(pm => !pm.released), 'cached/output maps are shared and never prematurely released');
const realNow = Date.now; let now = realNow(); Date.now = () => now;
try {
  fail = true; const before = sends; assert.equal(await GlowLoader.load('fixture/fail'), null);
  assert.equal(await GlowLoader.load('fixture/fail'), null); assert.equal(sends, before + 1);
  now += 30001; fail = false; assert.ok(await GlowLoader.load('fixture/fail'));
  imageStats.failDecode = true; assert.equal(await GlowLoader.load('fixture/decode'), null);
  const decodeCount = sends; assert.equal(await GlowLoader.load('fixture/decode'), null); assert.equal(sends, decodeCount);
  now += 30001; assert.ok(await GlowLoader.load('fixture/decode'));
  glowStats.failBlur = true; assert.equal(await GlowLoader.load('fixture/blur'), null);
  const blurCount = sends; assert.equal(await GlowLoader.load('fixture/blur'), null); assert.equal(sends, blurCount);
  now += 30001; assert.ok(await GlowLoader.load('fixture/blur'));
  const drain = await Promise.all([GlowLoader.load('fixture/throw'), ...Array.from({ length: 8 }, (_, i) => GlowLoader.load(`fixture/drain/${i}`))]);
  assert.equal(drain.filter(Boolean).length, 8);
  assert.equal(imageStats.sources, imageStats.sourceReleases);
  assert.ok(imageStats.pixels.every(pm => pm.width === 64 && pm.height === 36 && pm.released), 'temporary decoded maps are released');
  assert.ok(glowStats.pixels.every(pm => !pm.released));
} finally { Date.now = realNow; }
console.log('GlowLoader: max two tasks, queued dedup, LRU, failure expiry and temporary/shared map ownership passed');
