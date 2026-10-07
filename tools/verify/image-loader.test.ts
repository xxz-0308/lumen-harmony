import assert from 'node:assert/strict';
import { HttpRequest, HttpResponse, Platform } from '../../entry/src/main/ets/core/common/Transport';
import { ImageLoader } from '../../entry/src/main/ets/util/ImageLoader';

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
console.log('ImageLoader: max eight downloads, deduplication, queue drain and cache passed');
