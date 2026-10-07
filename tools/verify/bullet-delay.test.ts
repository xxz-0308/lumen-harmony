import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { BulletDelay, BULLET_LEAD_MS } from '../../entry/src/main/ets/danmaku/BulletDelay';

mock.timers.enable({ apis: ['setTimeout', 'Date'] });
const shown: string[] = [];
let latency = 7000;
const delay = new BulletDelay((text: string) => shown.push(text), () => latency - BULLET_LEAD_MS,
  () => Date.now());

// 7s of player cache: a bullet appears 6s after it arrives (one second before the picture).
delay.push('a', 0);
mock.timers.tick(5999);
assert.deepEqual(shown, []);
mock.timers.tick(1);
assert.deepEqual(shown, ['a']);

// The delay shrinking (catch-up) never lets a later message overtake an earlier one.
delay.push('b', 0);
latency = 2000;
mock.timers.tick(1000);
delay.push('c', 0);
mock.timers.tick(1000);
assert.deepEqual(shown, ['a'], 'c waits behind b');
mock.timers.tick(4000);
assert.deepEqual(shown, ['a', 'b', 'c']);

// No measurable latency (system player, or before the first frame) shows bullets immediately.
latency = 0;
delay.push('d', 0);
assert.deepEqual(shown, ['a', 'b', 'c', 'd']);

// Switching rooms drops what is still queued.
latency = 9000;
delay.push('stale', 0);
delay.clear();
mock.timers.tick(20000);
assert.deepEqual(shown, ['a', 'b', 'c', 'd']);
mock.timers.reset();
console.log('BulletDelay: follows player latency minus lead, keeps arrival order, immediate without latency, clear drops queue passed');
