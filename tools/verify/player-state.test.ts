import assert from 'node:assert/strict';
import { native, media } from './kit-media';
import { mock } from 'node:test';
import { BufferStats } from '../../entry/src/main/ets/player/BufferStats';
import { Log } from '../../entry/src/main/ets/util/Log';

Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {}
});
const { LivePlayer, PlayState } = await import('../../entry/src/main/ets/player/LivePlayer');
const player = new LivePlayer();
player.setSurface('test-surface');
await player.open(['https://example.test/one'], {}, 0);
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(player.state, PlayState.Playing);
assert.equal(player.firstFrame, true);
assert.deepEqual(native.lastStrategy, {
  preferredBufferDuration: 20,
  thresholdForAutoQuickPlay: 3600,
  preferredHdr: false
}, 'live sources must preserve a playback reserve, not just set byte capacity');
player.giveUp('forced failure');
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(player.state, PlayState.Error, 'native paused event cannot erase a user-visible error');
assert.equal(player.wantsPlayback, false);
player.stop();
await new Promise<void>((resolve) => setTimeout(resolve, 0));
native.emit('stateChange', 'completed');
native.emit('error', { code: 500 });
assert.equal(player.state, PlayState.Idle, 'late native events cannot restart a stopped room');
assert.equal(player.wantsPlayback, false);
assert.equal(player.currentUrl, '', 'stop clears the stale room URL');
const obsolete = player.open(['https://example.test/obsolete'], {}, 0);
const current = player.open(['https://example.test/current'], {}, 0);
await Promise.all([obsolete, current]);
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(player.currentUrl, 'https://example.test/current');
assert.equal(player.state, PlayState.Playing, 'latest source wins overlapping opens');
native.rejectBeforePlaying = true;
await player.open(['https://example.test/pip-return'], {}, 0);
await new Promise<void>((resolve) => setTimeout(resolve, 300));
assert.equal(player.state, PlayState.Playing, 'rejected play followed by native playing must not fail the room');
assert.equal(player.currentUrl, 'https://example.test/pip-return');
native.rejectWithoutPlaying = true;
await player.open(['https://example.test/fails', 'https://example.test/fallback'], {}, 0);
await new Promise<void>((resolve) => setTimeout(resolve, 300));
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(player.currentUrl, 'https://example.test/fallback', 'a real play failure still switches line');
assert.equal(player.state, PlayState.Playing);
player.release();
console.log('LivePlayer: error survives pause; stop, rapid opens and late native play isolate stale events');

function fields(line: string): Record<string, string> {
  return Object.fromEntries([...line.matchAll(/(\w+)=([^ ]+)/g)].map((m) => [m[1], m[2]]));
}
function expectFields(line: string, expected: Record<string, string | number | boolean>): void {
  const actual = fields(line);
  for (const [key, value] of Object.entries(expected)) assert.equal(actual[key], String(value), `${key}: ${line}`);
}

// Pure arithmetic: duplicate START does not reset its origin; snapshots never double count a pending span.
const stats = new BufferStats();
stats.observe(1000);
stats.expose(true, 1500);
stats.cache(800, 1600);
expectFields(stats.start(2000), { pair: 'start', valid: true, stallMs: 0 });
expectFields(stats.start(2100), { pair: 'duplicate-start', stallMs: 100 });
expectFields(stats.summary(2500), { observedMs: 1500, exposedMs: 1000, validCount: 1, totalMs: 500, maxMs: 500 });
assert.equal(stats.summary(2500), stats.summary(2500));
expectFields(stats.cacheText(2500), { cacheSample: 'last-event', cachedMs: 800, cacheAgeMs: 900 });
expectFields(stats.end(2700), { pair: 'paired', stallMs: 700 });
expectFields(stats.end(2800), { pair: 'orphan-end', stallMs: -1 });
stats.expose(false, 3000);
expectFields(stats.start(3200), { valid: false });
stats.end(3400);
stats.expose(true, 4000);
stats.start(4200);
expectFields(stats.interrupt(4500), { pair: 'interrupted', valid: true, stallMs: 300 });
stats.expose(false, 4500);
stats.stop(5000);
expectFields(stats.summary(9000), {
  observedMs: 4000, exposedMs: 2000, validCount: 2, totalMs: 1000, maxMs: 700,
  rawStart: 4, rawEnd: 3, paired: 2, duplicateStart: 1, orphanEnd: 1, interrupted: 1,
  rawTotalMs: 1200, rawMaxMs: 700, pending: false
});
stats.observe(10000);
stats.expose(true, 10000);
expectFields(stats.summary(10500), { observedMs: 4500, exposedMs: 2500 });
stats.clearCache();
expectFields(stats.cacheText(11000), { cachedMs: -1, cacheAgeMs: -1 });
const backwards = new BufferStats();
backwards.observe(1000);
backwards.expose(true, 1000);
backwards.cache(100, 1200);
backwards.start(1200);
expectFields(backwards.end(1100), { stallMs: 0 });
expectFields(backwards.cacheText(1100), { cacheAgeMs: 0 });
expectFields(backwards.summary(900), { exposedMs: 0, observedMs: 0, totalMs: 0, negativeDelta: 'clamp' });

async function flush(): Promise<void> {
  for (let i = 0; i < 12; i++) await Promise.resolve();
}
await flush();
const logs: string[] = [];
const allBufferLogs: string[] = [];
const originalInfo = Log.i;
const capture = (_tag: string, msg: string): void => {
  if (msg.startsWith('buffer ')) { logs.push(msg); allBufferLogs.push(msg); }
};
Log.i = capture;
const { BUFFERING_START: START, BUFFERING_END: END, CACHED_DURATION: CACHE } = media.BufferingInfoType;
const emitBuffer = (type: number, value = 0): void => native.emit('bufferingUpdate', type, value);
const last = (prefix: string): string => {
  const line = logs.findLast((entry) => entry.startsWith(`buffer ${prefix}`));
  assert.ok(line, `missing buffer ${prefix}`);
  return line;
};
let active: InstanceType<typeof LivePlayer> | null = null;
async function openTest(): Promise<InstanceType<typeof LivePlayer>> {
  native.currentTime = -1;
  native.deferPause = false;
  logs.length = 0;
  active = new LivePlayer();
  active.setSurface('test-surface');
  await active.open(['https://example.test/diagnostics'], {});
  await flush();
  return active;
}
async function closeTest(): Promise<void> {
  native.onReset = null;
  native.onSource = null;
  native.deferPause = false;
  active?.release();
  active = null;
  await flush();
}
mock.timers.enable({ apis: ['Date', 'setInterval', 'setTimeout'], now: 100000 });
// Node 24 mock Timeout objects lack real Node timers' numeric coercion; ArkTS checks handles >= 0.
function coercible<T extends object>(timer: T): T {
  Object.defineProperty(timer, Symbol.toPrimitive, { value: () => 1 });
  return timer;
}
const fakeTimeout = globalThis.setTimeout;
const fakeInterval = globalThis.setInterval;
globalThis.setTimeout = ((...args: Parameters<typeof setTimeout>) => coercible(fakeTimeout(...args))) as typeof setTimeout;
globalThis.setInterval = ((...args: Parameters<typeof setInterval>) => coercible(fakeInterval(...args))) as typeof setInterval;
try {
  const stall = await openTest();
  native.currentTime = 100;
  native.emit('speedDone', 100);
  expectFields(last('SPEED'), { mode: 100, positionMs: 100 });
  assert.equal(stall.state, PlayState.Playing, 'automatic catch-up is observed without pausing or resetting');
  emitBuffer(START);
  assert.equal(stall.state, PlayState.Buffering);
  mock.timers.tick(6000); // Past one old watchdog tick, but short of the 9s buffering failover.
  emitBuffer(END);
  assert.equal(stall.state, PlayState.Playing);
  expectFields(last('END'), { pair: 'paired', stallMs: 6000, sourceEpoch: 1, firstFrame: true });
  mock.timers.tick(5000);
  emitBuffer(END); // Duplicate END must not continuously reset the watchdog's position history.
  mock.timers.tick(5000);
  assert.equal(stall.state, PlayState.Playing, `watchdog must allow two samples before recovery: ${stall.errorText}`);
  mock.timers.tick(5000);
  assert.equal(stall.state, PlayState.Error, 'watchdog is rearmed after END even without a native playing event');
  await closeTest();

  const paused = await openTest();
  mock.timers.tick(1000);
  emitBuffer(START);
  native.deferPause = true;
  mock.timers.tick(2000);
  paused.pause();
  expectFields(last('INTERRUPT'), { reason: 'pause', stallMs: 2000, valid: true, wantPlay: false });
  emitBuffer(END);
  assert.equal(paused.state, PlayState.Buffering, 'late END cannot promote Buffering after pause intent');
  assert.equal(paused.wantsPlayback, false);
  native.state = 'paused';
  native.emit('stateChange', 'paused');
  emitBuffer(START);
  emitBuffer(END);
  assert.equal(paused.state, PlayState.Paused, 'native buffers ignored by UI remain observable while paused');
  expectFields(last('END'), { wantPlay: false, nativeState: 'paused', valid: false });
  mock.timers.tick(27000);
  expectFields(last('SUMMARY'), {
    reason: 'periodic', observedMs: 30000, exposedMs: 3000, rawStart: 2, rawEnd: 2,
    validCount: 1, totalMs: 2000, maxMs: 2000, interrupted: 1, orphanEnd: 1
  });
  paused.stop();
  const afterStop = logs.length;
  mock.timers.tick(60000);
  assert.equal(logs.length, afterStop, 'stop clears the periodic diagnostic timer');
  emitBuffer(START);
  emitBuffer(END);
  assert.equal(paused.state, PlayState.Idle);
  await closeTest();
  expectFields(last('SUMMARY'), { reason: 'release', observedMs: 30000, exposedMs: 3000, rawStart: 3, rawEnd: 3 });

  const swapping = await openTest();
  const beforeCache = logs.length;
  for (let i = 0; i < 100; i++) emitBuffer(CACHE, 1200);
  assert.equal(logs.length, beforeCache, 'cache duration updates are storage only');
  mock.timers.tick(500);
  emitBuffer(START);
  expectFields(last('START'), { cachedMs: 1200, cacheAgeMs: 500 });
  mock.timers.tick(400);
  native.onReset = () => {
    emitBuffer(END);
    assert.equal(swapping.state, PlayState.Buffering, 'reset END cannot claim seamless source is playing');
    expectFields(last('END'), { resetting: true, sourceEpoch: 1, pair: 'orphan-end' });
    emitBuffer(START);
    expectFields(last('START'), { resetting: true, valid: false });
  };
  native.onSource = () => {
    emitBuffer(START);
    emitBuffer(END);
    expectFields(last('END'), { firstFrame: false, sourceEpoch: 2, cachedMs: -1, valid: false });
  };
  await swapping.open(['https://example.test/new-source'], {}, 0, true);
  native.onReset = null;
  native.onSource = null;
  emitBuffer(END);
  expectFields(last('END'), { sourceEpoch: 2, pair: 'orphan-end', stallMs: -1 });
  assert.equal(swapping.state, PlayState.Playing);
  await closeTest();
  expectFields(last('SUMMARY'), { validCount: 1, totalMs: 400, interrupted: 2, rawStart: 3, rawEnd: 3 });

  const unavailable = await openTest();
  mock.timers.tick(5000);
  mock.timers.tick(5000);
  mock.timers.tick(5000);
  assert.equal(unavailable.state, PlayState.Playing, 'negative live position is not evidence of a frozen frame');
  native.currentTime = 100;
  mock.timers.tick(5000);
  mock.timers.tick(5000); // One actual strike.
  native.currentTime = -1;
  mock.timers.tick(5000);
  native.currentTime = NaN;
  mock.timers.tick(5000);
  native.currentTime = 100;
  mock.timers.tick(5000);
  mock.timers.tick(5000);
  assert.equal(unavailable.state, PlayState.Playing, 'unavailable positions clear old strikes and the reference');
  mock.timers.tick(5000);
  assert.equal(unavailable.state, PlayState.Error, 'valid frozen positions still trigger recovery');
  emitBuffer(START);
  emitBuffer(END);
  assert.equal(unavailable.state, PlayState.Error);
  expectFields(last('END'), { valid: false, wantPlay: false });
  await closeTest();

  const delayed = await openTest();
  mock.timers.tick(35000); // Delayed callback, not a nominal 30s interval.
  expectFields(last('SUMMARY'), { observedMs: 35000, exposedMs: 35000, validCount: 0 });
  emitBuffer(START);
  mock.timers.tick(1000);
  await closeTest();
  expectFields(last('SUMMARY'), { reason: 'release', totalMs: 1000, maxMs: 1000, interrupted: 1, pending: false });
  const afterRelease = logs.length;
  mock.timers.tick(60000);
  emitBuffer(START);
  native.emit('speedDone', 100);
  assert.equal(logs.length, afterRelease, 'release removes listener and diagnostic timer');
  assert.equal(delayed.state, PlayState.Idle);

  Log.i = (tag: string, msg: string): void => {
    if (msg.startsWith('buffer ')) throw new Error('diagnostic sink failed');
    originalInfo(tag, msg);
  };
  native.onSource = () => { emitBuffer(START); emitBuffer(END); };
  const resilient = await openTest();
  assert.equal(resilient.state, PlayState.Playing, 'logging failure during source assignment must not cause failover');
  emitBuffer(START);
  emitBuffer(END);
  assert.equal(resilient.state, PlayState.Playing);
  mock.timers.tick(30000);
  assert.equal(resilient.state, PlayState.Playing, 'summary logging failure must not cause recovery');
  resilient.stop();
  await closeTest();
  Log.i = capture;
  assert.ok(allBufferLogs.length > 0);
  assert.ok(allBufferLogs.every((line) => !/https?:\/\/|example\.test/.test(line)), 'diagnostics contain no URL or media content');
} finally {
  await closeTest();
  mock.timers.reset();
  Log.i = originalInfo;
}
console.log('LivePlayer: pause/reset END guards, watchdog rearm, unavailable positions, native buffer accounting and timer cleanup passed');
