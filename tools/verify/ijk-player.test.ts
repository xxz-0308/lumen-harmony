import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { latest, ops, players } from './kit-ijk';

Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {}
});
const { IjkLivePlayer } = await import('../../entry/src/main/ets/player/IjkLivePlayer');
const { PlayState, PlayerEngine } = await import('../../entry/src/main/ets/player/PlayerApi');
const tick = (): Promise<void> => new Promise<void>((resolve) => setImmediate(resolve));
const RENDER = 3;
const BUF_START = 701;
const BUF_END = 702;
const ctx = {};

// Opening before the XComponent loads waits for it, then starts the requested line.
const player = new IjkLivePlayer();
assert.equal(player.engine, PlayerEngine.Ijk);
await player.open(['https://a.test/1.flv', 'https://a.test/2.flv'], { 'User-Agent': 'x' }, 1);
assert.equal(players.length, 0, 'no native player before the surface exists');
assert.equal(player.state, PlayState.Loading);
player.bindNative(ctx, 'video_0');
await tick();
let p = latest();
assert.equal(p.url, 'https://a.test/2.flv');
assert.equal(p.id, 'video_0');
assert.equal(p.options.get('4/mediacodec-all-videos'), '1');
assert.equal(p.options.get('4/first-high-water-mark-ms'), '1500');
assert.equal(p.options.get('4/last-high-water-mark-ms'), '5000', 'the native option rejects values above 5000');
assert.equal(p.options.get('4/infbuf'), '1');
assert.equal(p.options.get('4/soundtouch'), '1');
assert.equal(p.options.get('1/user_agent'), 'x', 'User-Agent replaces the FFmpeg default instead of duplicating it');
assert.equal(p.options.get('headers'), undefined, 'no other headers were given');
assert.ok(ops.includes('setup:video_0:1'), 'hardware decoding renders through surface mode');
p.emitPrepared();
assert.equal(player.state, PlayState.Playing);
p.emitInfo(RENDER);
assert.equal(player.firstFrame, true);

// Native buffering maps onto the shared state model.
p.emitInfo(BUF_START);
assert.equal(player.state, PlayState.Buffering);
p.emitInfo(BUF_END);
assert.equal(player.state, PlayState.Playing);

// A line switch releases the old native player BEFORE setting up the next one on the same ID.
ops.length = 0;
player.selectLine(0);
await tick();
const order = ops.filter((op: string) => op.startsWith('release') || op.startsWith('setup'));
assert.deepEqual(order, ['release:https://a.test/2.flv', 'setup:video_0:1']);
const old = p;
p = latest();
assert.equal(p.url, 'https://a.test/1.flv');
old.emitError(-10000);
old.emitInfo(BUF_START);
assert.equal(player.state, PlayState.Loading, 'callbacks from a released player are ignored');
p.emitPrepared();
p.emitInfo(RENDER);

// Errors fail over to the next line; when every line failed the owner may recover.
let exhausted = '';
player.onLinesExhausted = (reason: string): boolean => {
  exhausted = reason;
  return true;
};
p.emitError(-10000, 0);
await tick();
assert.equal(latest().url, 'https://a.test/2.flv', 'error moves to the other line');
assert.match(player.notice, /线路 2/);
latest().emitError(-10000, 0);
await tick();
assert.match(exhausted, /播放出错/, 'second failure hands recovery to the owner');

// A completed live stream asks the owner to re-resolve (signed URL expiry).
let ended = 0;
player.onStreamEnded = (): void => {
  ended++;
};
await player.open(['https://a.test/3.flv'], {}, 0);
await tick();
latest().emitPrepared();
latest().emitInfo(RENDER);
latest().emitCompletion();
assert.equal(ended, 1);

// Seamless reopen keeps the last picture and flags reconnecting until the new first frame.
await player.open(['https://a.test/4.flv'], {}, 0, true);
await tick();
assert.equal(player.firstFrame, true);
assert.equal(player.reconnecting, true);
latest().emitInfo(RENDER);
assert.equal(player.reconnecting, false);

// Pause stops the native player; resume reopens at the live edge.
ops.length = 0;
player.pause();
assert.equal(player.state, PlayState.Paused);
assert.equal(player.wantsPlayback, false);
assert.ok(ops.includes('pause:https://a.test/4.flv'));
player.resume();
await tick();
assert.equal(player.wantsPlayback, true);
assert.ok(ops.includes('release:https://a.test/4.flv') && latest().url === 'https://a.test/4.flv' &&
  !latest().released, 'resume replaces the paused native player');
latest().emitPrepared();
latest().emitInfo(RENDER);

// Volume reaches the current native player and later ones.
player.setVolume(0.4);
assert.equal(latest().volume, '0.4');

// A replaced XComponent (layout rebuild) reopens on the new surface ID.
player.unbindNative('other');
assert.equal(latest().released, false, 'unrelated surfaces are ignored');
player.unbindNative('video_0');
await tick();
assert.equal(latest().released, true, 'destroying the surface releases its native player');
player.bindNative({}, 'video_1');
await tick();
assert.equal(latest().id, 'video_1');
assert.equal(latest().released, false);
assert.equal(latest().volume, '0.4');

// Audio focus loss pauses like the user pressing pause.
latest().emitPrepared();
latest().emitInfo(RENDER);
latest().interrupt?.({ hintType: 2 });
assert.equal(player.wantsPlayback, false);

// Stop and release tear the native player down and ignore anything late.
player.resume();
await tick();
player.stop();
await tick();
assert.equal(player.state, PlayState.Idle);
assert.equal(latest().released, true);
latest().emitError(-1);
assert.equal(player.state, PlayState.Idle);

// Stall watchdog and gentle latency catch-up use timers.
mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
try {
  const timed = new IjkLivePlayer();
  timed.bindNative(ctx, 'video_t');
  await timed.open(['https://t.test/1.flv', 'https://t.test/2.flv'], {}, 0);
  await tick();
  let n = latest();
  n.emitPrepared();
  n.emitInfo(RENDER);
  // 12s+ of reserve: speed up a little; back under 8s: normal speed.
  ops.length = 0;
  n.cachedMs = 13000;
  mock.timers.tick(2000);
  assert.deepEqual(ops.filter((op: string) => op.startsWith('speed')), ['speed:1.05']);
  n.cachedMs = 10000;
  mock.timers.tick(2000);
  assert.equal(ops.filter((op: string) => op.startsWith('speed')).length, 1, 'hysteresis between 8s and 12s');
  n.cachedMs = 7000;
  mock.timers.tick(2000);
  assert.deepEqual(ops.filter((op: string) => op.startsWith('speed')), ['speed:1.05', 'speed:1']);
  // A stall during catch-up returns to normal speed immediately.
  n.cachedMs = 13000;
  mock.timers.tick(2000);
  n.emitInfo(BUF_START);
  assert.deepEqual(ops.filter((op: string) => op.startsWith('speed')).slice(-1), ['speed:1']);
  // Buffering longer than 15s switches line; 14s does not.
  mock.timers.tick(14000);
  assert.equal(latest(), n);
  mock.timers.tick(1000);
  await tick();
  assert.equal(latest().url, 'https://t.test/2.flv', 'a 15s stall fails over');
  // No first frame within 12s on the last untried line: every line failed, so it gives up.
  n = latest();
  mock.timers.tick(11000);
  assert.equal(timed.state, PlayState.Loading);
  mock.timers.tick(1000);
  await tick();
  assert.equal(timed.state, PlayState.Error);
  assert.match(timed.errorText, /连接超时/);
  // A pause longer than 30s drops the connection (infbuf would buffer without bound); resume reopens.
  await timed.open(['https://t.test/p.flv'], {}, 0);
  await tick();
  n = latest();
  n.emitPrepared();
  n.emitInfo(RENDER);
  timed.resume();
  await tick();
  assert.equal(latest(), n, 'resume while already playing does not reconnect');
  timed.pause();
  mock.timers.tick(29000);
  await tick();
  assert.equal(n.released, false, 'short pauses keep the connection');
  mock.timers.tick(1000);
  await tick();
  assert.equal(n.released, true, 'long pauses release it');
  timed.resume();
  await tick();
  assert.equal(latest().url, 'https://t.test/p.flv');
  assert.equal(latest().released, false);
  timed.release();
  await tick();
  assert.equal(latest().released, true);
  const count = players.length;
  mock.timers.tick(60000);
  await tick();
  assert.equal(players.length, count, 'a released player never creates another native player');
} finally {
  mock.timers.reset();
}

console.log('IjkLivePlayer: pending surface, options, buffering states, ordered release, stale callbacks, failover, ' +
  'completion, seamless reopen, pause/resume, surface rebinding, audio focus, stall/start timeouts and ' +
  'gentle catch-up, long-pause release passed');
