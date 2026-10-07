import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { runInNewContext } from 'node:vm';
import { FlvHandoff, FlvMediaHistory } from '../../entry/src/main/ets/player/FlvHandoff';
import { FlvTimestampNormalizer } from '../../entry/src/main/ets/player/FlvTimestampNormalizer';

const header = new Uint8Array([70, 76, 86, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0]);
function tag(type: number, time: number, body: number[]): Uint8Array {
  const size = body.length;
  const out = new Uint8Array(size + 15);
  out.set([type, (size >>> 16) & 255, (size >>> 8) & 255, size & 255,
    (time >>> 16) & 255, (time >>> 8) & 255, time & 255, (time >>> 24) & 255, 0, 0, 0]);
  out.set(body, 11);
  const prev = size + 11;
  out.set([(prev >>> 24) & 255, (prev >>> 16) & 255, (prev >>> 8) & 255, prev & 255], size + 11);
  return out;
}
function join(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, part) => n + part.length, 0));
  let offset = 0;
  for (const part of parts) { out.set(part, offset); offset += part.length; }
  return out;
}
function time(frame: Uint8Array): number {
  return (frame[4] * 65536 + frame[5] * 256 + frame[6] + frame[7] * 16777216) >>> 0;
}
// Length-prefixed NAL framing, not a decoder fixture. Synthetic content labels are not H.264 pictures.
const videoHeader = tag(9, 0, [0x17, 0, 0, 0, 0, 1, 100, 0, 31, 0xff, 0xe1, 0, 2, 0x67, 100, 1, 0, 1, 0x68]);
const audioHeader = tag(8, 0, [0xaf, 0, 0x12, 0x10]);
const prefix = [header, videoHeader, audioHeader];
function video(id: number, raw = id * 100, key = id % 10 === 0, cts = 0): Uint8Array {
  return tag(9, raw, [key ? 0x17 : 0x27, 1, (cts >>> 16) & 255, (cts >>> 8) & 255, cts & 255,
    0, 0, 0, 5, key ? 0x65 : 0x41, (id >>> 24) & 255, (id >>> 16) & 255, (id >>> 8) & 255, id & 255]);
}
function audio(id: number, raw = id * 100 + 10): Uint8Array {
  return tag(8, raw, [0xaf, 1, (id >>> 24) & 255, (id >>> 16) & 255, (id >>> 8) & 255, id & 255]);
}
/** One IDR picture of a given payload size, framed like a real FLV keyframe. */
function bigKey(raw: number, bytes: number): Uint8Array {
  const nal = new Array<number>(bytes).fill(7);
  nal[0] = 0x65; // NAL type 5
  const len = nal.length;
  return tag(9, raw, [0x17, 1, 0, 0, 0, (len >>> 24) & 255, (len >>> 16) & 255, (len >>> 8) & 255,
    len & 255, ...nal]);
}
function av(first: number, last: number, baseline = 0, bframes = false): Uint8Array[] {
  const result: Uint8Array[] = [];
  for (let id = first; id <= last; id++) {
    const cts = !bframes || id % 10 === 0 ? 0 : id % 2 === 0 ? 40 : -20;
    result.push(video(id, baseline + id * 100, id % 10 === 0, cts), audio(id, baseline + id * 100 + 10));
  }
  return result;
}
function isMedia(frame: Uint8Array): boolean {
  return (frame[0] === 9 || frame[0] === 8) && frame[12] === 1;
}
function contentId(frame: Uint8Array): number {
  const pos = frame[0] === 9 ? 21 : 13;
  return (frame[pos] * 16777216 + frame[pos + 1] * 65536 + frame[pos + 2] * 256 + frame[pos + 3]) >>> 0;
}
function normalized(parts: Uint8Array[]): Uint8Array { return join(new FlvTimestampNormalizer().push(join(parts))); }
function admit(history: FlvMediaHistory, frames: Uint8Array[], raw: number[]) {
  frames.forEach((frame, i) => { if (raw[i] >= 0) history.observe(frame, raw[i]); });
}
function setup(last = 109, oldBaseline = 0) {
  const history = new FlvMediaHistory();
  const parser = new FlvTimestampNormalizer();
  let tail = 0;
  const emitOld = (parts: Uint8Array[]) => {
    const frames = parser.push(join(parts));
    admit(history, frames, parser.rawTimestamps);
    if (frames.length) tail = time(frames.at(-1)!);
    return frames;
  };
  const old = emitOld([...prefix, ...av(0, last, oldBaseline)]);
  const handoff = new FlvHandoff(7, 10, tail, videoHeader, audioHeader, history);
  const hold = (parts: Uint8Array[] = [video(110, oldBaseline + 11000)]) => {
    const frames = parser.push(join(parts));
    return handoff.holdBoundary(frames[0], parser.rawTimestamps[0], tail);
  };
  return { history, handoff, emitOld, hold, old, tail: () => tail };
}

// Common raw clocks + identical IDR preserve ALL old single-stream bytes, not merely monotonic DTS.
for (const oldBaseline of [0, 300000000, 0xffffd000]) {
  for (const baseline of [0, 700000000, 0xffffd000]) {
    const s = setup(109, oldBaseline);
    assert.equal(s.handoff.push(join([...prefix, ...av(90, 95, baseline)])).length, 0);
    assert.equal(s.handoff.matchedPackets, 12, 'six distinct packets of EACH track');
    assert.equal(s.handoff.pendingReason, 'waiting-old-idr');
    const before = s.history.summary();
    assert.equal(s.hold(), true);
    const frames = s.handoff.push(join(av(96, 113, baseline)));
    assert.equal(s.handoff.ready, true);
    assert.deepEqual(frames.filter(isMedia).map(contentId), [110, 110, 111, 111, 112, 112, 113, 113]);
    assert.equal(s.handoff.firstOutputTimestamp, 11000, 'no +1 compression or inserted GOP delay');
    assert.equal(s.history.summary(), before, 'neither held old bytes nor parsed candidate bytes are history');
    assert.deepEqual(join([...s.old, ...frames]), normalized([...prefix, ...av(0, 113, oldBaseline)]));
    admit(s.history, frames, s.handoff.rawTimestamps);
    assert.equal(s.history.tailRaw, (oldBaseline + 11310) >>> 0);
  }
}
for (const size of [1, 2, 7, 17, 64, 511]) {
  const s = setup();
  const feed = (bytes: Uint8Array) => {
    const out: Uint8Array[] = [];
    for (let p = 0; p < bytes.length; p += size) out.push(...s.handoff.push(bytes.slice(p, p + size)));
    return out;
  };
  feed(join([...prefix, ...av(90, 95, 700000000)]));
  assert.equal(s.hold(), true);
  const frames = feed(join(av(96, 112, 700000000)));
  assert.deepEqual(join([...s.old, ...frames]), normalized([...prefix, ...av(0, 112)]), `fragment ${size}`);
}
// Without an old barrier even a proved, leading candidate cannot silently skip a GOP.
{
  const s = setup();
  assert.equal(s.handoff.push(join([...prefix, ...av(90, 140)])).length, 0);
  assert.equal(s.handoff.ready, false);
  assert.equal(s.hold(), false, 'candidate already passed this key; do not manufacture a later boundary');
  const ahead = setup();
  ahead.handoff.push(join([...prefix, ...av(120, 140)]));
  assert.equal(ahead.handoff.pendingReason, 'unproven-overlap');
  assert.equal(ahead.hold(), false);
}
// The boundary is judged on the OLD stream's own keyframe, a 300-400KB packet on 2K60 lines.
{
  const s = setup();
  s.handoff.push(join([...prefix, ...av(90, 95, 700000000)]));
  assert.equal(s.handoff.matchedPackets, 12);
  const raw = s.history.tailRaw + 1000;
  assert.equal(s.handoff.holdBoundary(bigKey(raw, 400 * 1024), raw, s.tail()), true,
    'a real-sized keyframe must still be provable');
  assert.match(s.handoff.boundaryDiagnostics(), /noKey=0 .*accepted=1/);
}
for (const kind of ['static', 'single-key', 'periodic']) {
  const history = new FlvMediaHistory();
  const old: Uint8Array[] = [];
  const next: Uint8Array[] = [];
  for (let i = 0; i <= 130; i++) {
    const id = kind === 'periodic' ? i % 10 : 0;
    if (i <= 100) old.push(video(id, i * 100, i % 10 === 0), audio(id, i * 100 + 10));
    if (i >= 80) next.push(video(kind === 'single-key' && i !== 80 ? 999 : id, i * 100 + 700000000, i % 10 === 0),
      audio(id, i * 100 + 700000010));
  }
  for (const frame of [...prefix.slice(1), ...old]) history.observe(frame, time(frame));
  const h = new FlvHandoff(7, 10, 10010, videoHeader, audioHeader, history);
  assert.equal(h.push(join([...prefix, ...next])).length, 0, kind);
  assert.equal(h.matchedPackets, 0, kind);
  if (kind === 'periodic') assert.equal(h.pendingReason, 'ambiguous-overlap');
}
for (const mismatch of ['offset', 'interval', 'video-only']) {
  const s = setup();
  const next: Uint8Array[] = [];
  for (let i = 90; i <= 110; i++) {
    const t = i * (mismatch === 'interval' ? 101 : 100);
    next.push(video(i, t));
    if (mismatch !== 'video-only') next.push(audio(i, t + 10 + (mismatch === 'offset' ? 500 : 0)));
  }
  s.handoff.push(join([...prefix, ...next]));
  assert.equal(s.handoff.matchedPackets, 0, mismatch);
  assert.equal(s.hold(), false, mismatch);
}
// A codec id change is never spliceable: the decoder would be handed a different format.
{
  const s = setup();
  assert.throws(() => s.handoff.push(join([header, tag(9, 0, [0x1c, 0, 0, 0, 0, 1, 100]), ...av(90, 110)])),
    /Unsafe FLV/);
  assert.match(s.handoff.pendingReason, /codec/);
}
// A live CDN hands two connections of one session different encoder configs (measured 49 vs 50 bytes
// on a 2K60 Douyu line) while the coded frames stay byte-identical, and the already-playing
// connection keeps decoding under its own config. Identity therefore rests on the packet proof and a
// byte-identical boundary IDR, and the candidate's config is replayed at the splice rather than
// failing the handoff.
// Only the drifted track's config travels: the other track still matches the decoder's state.
{
  const videoDrift = tag(9, 0, [0x17, 0, 0, 0, 0, 1, 100, 0, 31, 0xff, 0xe2, 0, 2, 0x67, 100, 1, 0, 1, 0x68]);
  const audioDrift = tag(8, 0, [0xaf, 0, 0x13, 0x10]);
  for (const [candidatePrefix, carriedConfig] of [
    [[header, videoDrift, audioHeader], videoDrift],
    [[header, videoHeader, audioDrift], audioDrift]
  ]) {
    const s = setup();
    assert.equal(s.handoff.push(join([...candidatePrefix, ...av(90, 95, 700000000)])).length, 0);
    assert.equal(s.handoff.configDiffers, true, 'config drift is recorded, not fatal');
    assert.equal(s.handoff.matchedPackets, 12, 'identity still rests on the packet proof');
    assert.equal(s.handoff.pendingReason, 'waiting-old-idr');
    assert.equal(s.hold(), true);
    const frames = s.handoff.push(join(av(96, 113, 700000000)));
    assert.equal(s.handoff.ready, true);
    assert.deepEqual(frames.filter(isMedia).map(contentId), [110, 110, 111, 111, 112, 112, 113, 113]);
    const carried = frames.filter((frame) => !isMedia(frame));
    assert.equal(carried.length, 1, 'exactly the differing config reaches the decoder');
    assert.deepEqual(carried[0].slice(11), carriedConfig.slice(11), 'and it is the candidate own');
    assert.equal(frames.indexOf(carried[0]), 0, 'config precedes the boundary IDR');
  }
}

// Measured on device: the candidate's parse path is cheaper than the old stream's, so its newest
// frame runs marginally ahead and every old keyframe arrives already discarded (diag passed=N,
// accepted=0). Holding a boundary is then impossible, which used to end every attempt in a full
// player reset and the content rewind that follows it. The relay gives the exact splice two seconds
// and then allows a forward cut to the candidate's own keyframe.
{
  const s = setup();
  s.handoff.push(join([...prefix, ...av(90, 95, 700000000)]));
  assert.equal(s.handoff.matchedPackets, 12);
  assert.equal(s.handoff.ready, false);
  // A keyframe still behind the forwarded position is never a splice point, cut allowed or not.
  assert.equal(s.handoff.push(join([video(100, 700010000)]), 10910, true).length, 0);
  assert.equal(s.handoff.ready, false);
  // Without the cut allowed this keyframe stays dropped and the attempt keeps waiting.
  assert.equal(s.handoff.push(join([video(110, 700011000)]), 10910, false).length, 0);
  assert.equal(s.handoff.ready, false);
  assert.equal(s.handoff.pendingReason, 'waiting-old-idr');
  // A caller that supplies no forwarded position can never trigger a cut.
  assert.equal(s.handoff.push(join([video(110, 700011000)]), 0, true).length, 0);
  assert.equal(s.handoff.ready, false);
  // With it allowed the keyframe becomes the splice point, ahead of what the player already has.
  const frames = s.handoff.push(join([video(110, 700011000)]), 10910, true);
  assert.equal(s.handoff.ready, true);
  assert.equal(s.handoff.cutForward, true);
  assert.equal(s.handoff.pendingReason, 'candidate-forward-cut');
  assert.equal(s.handoff.contentAdvanceMs, 90, 'splice lands 90ms ahead, never behind');
  assert.equal(s.handoff.firstOutputTimestamp, 10911, 'output continues from the forwarded clock');
  assert.deepEqual(frames.filter(isMedia).map(contentId), [110]);
}
{
  const s = setup();
  s.handoff.push(join([header, ...av(90, 95)]));
  assert.equal(s.hold(), false, 'missing configs');
  const fakeKey = video(110); fakeKey[20] = 0x41;
  assert.equal(FlvHandoff.isIdr(fakeKey, videoHeader), false, 'FLV frameType alone is not IDR evidence');
  const malformed = video(110); malformed[19] = 200;
  assert.equal(FlvHandoff.isIdr(malformed, videoHeader), false);
}
for (const reset of ['old', 'candidate', 'diverged']) {
  const s = setup();
  s.handoff.push(join([...prefix, ...av(90, 95)]));
  if (reset === 'old') s.emitOld([video(999, 9000)]);
  assert.throws(() => s.handoff.push(reset === 'candidate' ? video(90) : reset === 'diverged' ? video(999, 9600) : video(96)), /Unsafe FLV/);
  assert.equal(s.handoff.pendingReason, reset === 'old' ? 'old-timeline-changed' : reset === 'candidate' ? 'candidate-timeline-changed' : 'overlap-diverged');
}
// A boundary cannot be moved ahead to hide queued B-frame presentation time.
{
  const s = setup();
  s.handoff.push(join([...prefix, ...av(90, 95)]));
  s.history.observe(video(109, 10900, false, 200), 10900);
  assert.equal(s.hold(), false);
}
// Keep unplayed late audio (even DTS before the IDR), or reject a different interleaving safely.
for (const beforeKey of [false, true]) {
  const s = setup();
  s.handoff.push(join([...prefix, ...av(90, 109)]));
  assert.equal(s.hold(), true);
  const late = audio(110, 10995);
  if (beforeKey) {
    assert.throws(() => s.handoff.push(join([late, video(110)])), /Unsafe FLV/);
    assert.equal(s.handoff.pendingReason, 'audio-before-idr');
  } else {
    const frames = s.handoff.push(join([video(110), late, video(111)]));
    assert.deepEqual(frames.filter(isMedia).map(contentId), [110, 110, 111]);
    assert.deepEqual(join([...s.old, ...frames]), normalized([...prefix, ...av(0, 109), video(110), late, video(111)]));
  }
}
// Retain the diagnostic scalar fields and bounded identity history; never keep payloads here.
{
  const history = new FlvMediaHistory();
  for (let i = 0; i < 2000; i++) { history.observe(video(i, i * 10), i * 10); history.observe(audio(i, i * 10), i * 10); }
  assert.equal(history.video.length, 512); assert.equal(history.audio.length, 512);
  assert.deepEqual(Object.keys(history.video[0]), ['raw', 'key', 'output']);
  assert.match(history.summary(), /videoRawMs=5110 videoOutputMs=5110/);
  assert.match(history.summary(), /audioRawMs=5110 audioOutputMs=5110/);
  assert.match(history.summary(), /videoTimingDistortions=0 videoMaxStepErrorMs=0/);
  assert.match(history.summary(), /audioTimingDistortions=0 audioMaxStepErrorMs=0/);
  // Live 2K60 Douyu keyframes measure p50=306KB / max=403KB. A 256KB ceiling turned every one of
  // them into an empty key, so no boundary could be proven and each signed-URL renewal fell back
  // to a full player reset (the reported ~2s rewind). Real keyframes must stay provable.
  history.observe(bigKey(20000, 400 * 1024), 20000);
  assert.notEqual(history.video.at(-1)!.key, '');
  const oversize = new Array<number>(4 * 1024 * 1024 + 6).fill(1);
  oversize[0] = 0x17;
  oversize[1] = 1;
  history.observe(tag(9, 20010, oversize), 20010);
  assert.equal(history.video.at(-1)!.key, '', 'only a pathological packet is refused');
}

// Equal spans can conceal alternating compressed/stretched packet intervals; a 1ms error is tolerated.
{
  const history = new FlvMediaHistory();
  [0, 0, 40, 60].forEach((output, i) => history.observe(audio(i, output), i * 20));
  assert.match(history.summary(), /audioRawMs=60 audioOutputMs=60 audioTimingDistortions=2 audioMaxStepErrorMs=20/);
  const wrapped = new FlvMediaHistory();
  [0xfffffff0, 4, 24].forEach((raw, i) => wrapped.observe(video(i, [0, 21, 40][i]), raw));
  assert.match(wrapped.summary(), /videoRawMs=40 videoOutputMs=40 videoTimingDistortions=0 videoMaxStepErrorMs=1/);
}

// Compile and run the real RelayClient event handlers. Only native transport/logging are mocked.
const { build } = createRequire(import.meta.url)('esbuild');
const relayPath = fileURLToPath(new URL('../../../entry/src/main/ets/player/DouyuStreamRelay.ets', import.meta.url));
const compiled = await build({
  stdin: { contents: readFileSync(relayPath, 'utf8') + '\nexport { RelayClient, RelayTarget };', resolveDir: dirname(relayPath), loader: 'ts' },
  bundle: true, platform: 'node', format: 'cjs', write: false,
  loader: { '.ets': 'ts' }, resolveExtensions: ['.ts', '.ets', '.js'],
  plugins: [{ name: 'offline-relay-fixture', setup(build: any) {
    build.onResolve({ filter: /^@kit\.|^\.\.\/util\/Log$/ }, (args: any) => ({ path: args.path, namespace: 'fixture' }));
    build.onLoad({ filter: /.*/, namespace: 'fixture' }, (args: any) => ({ contents:
      args.path === '@kit.NetworkKit' ? 'export const http = fixture.http; export const socket = {};' :
      args.path === '../util/Log' ? 'export const Log = fixture.Log;' : 'export const cryptoFramework = {};'
    }));
  } }]
});
class Events {
  callbacks = new Map<string, (...args: any[]) => void>();
  on(event: string, callback: (...args: any[]) => void) { this.callbacks.set(event, callback); }
  emit(event: string, value?: any) { this.callbacks.get(event)?.(value); }
}
class Request extends Events {
  destroyed = false;
  rejectRequest: (e: Error) => void = () => {};
  resolveRequest: (status: number) => void = () => {};
  requestInStream() { return new Promise<number>((resolve, reject) => { this.resolveRequest = resolve; this.rejectRequest = reject; }); }
  destroy() { this.destroyed = true; }
  data(parts: Uint8Array[]) { this.emit('dataReceive', join(parts).buffer); }
}
const flush = async () => { for (let i = 0; i < 100; i++) await Promise.resolve(); };
async function relayFixture(last = 100, bframes = false) {
  const requests: Request[] = [];
  const timers = new Map<number, { fn: () => void; at: number }>();
  const logs: string[] = [];
  const sent: Uint8Array[] = [];
  const conn = new Events() as Events & { send: (x: any) => Promise<void>; close: () => Promise<void> };
  let closed = false, blocked = false, failSend = false, now = 0, id = 0;
  let release: (() => void) | undefined;
  conn.send = async (info: any) => {
    if (blocked) await new Promise<void>((resolve) => { release = resolve; });
    if (failSend) throw new Error('fixture send failure');
    if (!closed) sent.push(new Uint8Array(info.data));
  };
  conn.close = async () => { closed = true; release?.(); };
  const at = (time: number, fn: () => void) => { timers.set(++id, { fn, at: time }); return id; };
  const tick = async (until: number) => {
    assert.ok(until >= now);
    for (;;) {
      const first = [...timers].sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
      if (!first || first[1].at > until) break;
      now = first[1].at; timers.delete(first[0]); first[1].fn(); await flush();
    }
    now = until; await flush();
  };
  const module = { exports: {} as any };
  runInNewContext(compiled.outputFiles[0].text, {
    module, exports: module.exports, Uint8Array, ArrayBuffer, Promise, Date: { now: () => now },
    setTimeout: (fn: () => void, ms: number) => at(now + ms, fn), clearTimeout: (n: number) => timers.delete(n),
    fixture: {
      http: { createHttp: () => { const req = new Request(); requests.push(req); return req; }, RequestMethod: { GET: 0 } },
      Log: { i: (_tag: string, text: string) => logs.push(text), w: (_tag: string, text: string) => logs.push(text) }
    }
  });
  const { RelayClient, RelayTarget, DouyuStreamRelay } = module.exports;
  const relay = new DouyuStreamRelay();
  const target = new RelayTarget('https://not-contacted.invalid/live.flv', {});
  const client = new RelayClient(conn, () => target, () => {});
  relay.clients.add(client);
  conn.emit('message', { message: new TextEncoder().encode(`GET /${'0'.repeat(32)}.flv HTTP/1.1\r\n\r\n`).buffer });
  requests[0].data([...prefix, ...av(0, last, 0, bframes)]); await flush();
  return { client, relay, target, requests, logs, sent, conn, timers, at, tick, now: () => now,
    closed: () => closed, body: () => join(sent.slice(1)),
    block: () => { blocked = true; }, unblock: () => { blocked = false; release?.(); },
    failSend: () => { failSend = true; }, jumpWithoutTimers: (value: number) => { now = value; }
  };
}
function noSuccess(f: Awaited<ReturnType<typeof relayFixture>>) {
  assert.ok(!f.logs.some((line) => line.includes('proof=media-sequence')));
}
function expectBody(f: Awaited<ReturnType<typeof relayFixture>>, parts: Uint8Array[]) {
  assert.deepEqual(f.body(), normalized([...prefix, ...parts]), 'exact byte sequence incl. DTS/CTS, audio, metadata and tag sizes');
  assert.equal(f.sent.filter((part) => part[0] === 72).length, 1, 'one HTTP response / same player connection');
}
// Every candidate media packet is EXACTLY 50/200ms late: the previous chasing-tail algorithm fails.
// Assertions compare against the entire old-only byte stream, independently of content hashes.
for (const delay of [50, 200]) {
  const f = await relayFixture(79, true);
  const result = f.client.renew(f.target);
  f.requests[1].data(prefix);
  for (let id = 80; id <= 125; id++) {
    const old = av(id, id, 0, true), next = av(id, id, 700000000, true);
    for (let track = 0; track < 2; track++) {
      const arrival = (id - 80) * 100 + track * 10;
      f.at(arrival, () => f.requests[0].data([old[track]]));
      f.at(arrival + delay, () => f.requests[1].data([next[track]]));
    }
  }
  f.at(1001, () => {
    assert.equal(f.client.mediaHistory.tailRaw, 8910, 'withheld IDR90 is not history');
    assert.equal(f.client.lastTimestamp, 8910, 'actual admitted tail stops before IDR');
    assert.equal(f.requests[0].destroyed, false);
    assert.ok(f.client.heldBytes > 0 && f.client.heldBytes <= 512 * 1024);
  });
  await f.tick(4510 + delay);
  assert.equal(await result, true);
  assert.equal(f.closed(), false); assert.equal(f.requests[0].destroyed, true);
  expectBody(f, av(0, 125, 0, true));
  // Diagnostics may interleave other relay lines; match by content, not by position.
  assert.ok(f.logs.some((line) => new RegExp(`matched=12 .*freezeWait=${delay} .*boundary=same-idr boundaryOutput=9000`).test(line)));
  assert.ok(!f.logs.some((line) => /700000000|https:|fingerprint/.test(line)));
  // A second renewal uses admitted common-clock history from the first handoff, not parser state.
  const nextResult = f.client.renew(f.target);
  f.requests[2].data([...prefix, ...av(110, 125, 1900000000, true)]);
  const begin = f.now() + 10;
  for (let id = 126; id <= 150; id++) {
    const old = av(id, id, 700000000, true), next = av(id, id, 1900000000, true);
    for (let track = 0; track < 2; track++) {
      const arrival = begin + (id - 126) * 100 + track * 10;
      f.at(arrival, () => f.requests[1].data([old[track]]));
      f.at(arrival + delay, () => f.requests[2].data([next[track]]));
    }
  }
  await f.tick(begin + 2410 + delay);
  assert.equal(await nextResult, true);
  expectBody(f, av(0, 150, 0, true));
  assert.equal(f.logs.filter((line) => line.includes('proof=media-sequence')).length, 2);
  f.requests[0].emit('dataEnd'); f.requests[1].emit('dataEnd'); await flush();
  assert.equal(f.closed(), false, 'stale EOF from both retired requests is ignored');
  f.client.close(); assert.equal(f.timers.size, 0);
}

// A consistently late 500ms connection cannot meet the barrier; no amount of old progress helps.
{
  const f = await relayFixture(79);
  const result = f.client.renew(f.target); f.requests[1].data(prefix);
  for (let id = 80; id <= 125; id++) {
    const old = av(id, id), next = av(id, id, 700000000);
    for (let track = 0; track < 2; track++) {
      const arrival = (id - 80) * 100 + track * 10;
      f.at(arrival, () => f.requests[0].data([old[track]]));
      f.at(arrival + 500, () => f.requests[1].data([next[track]]));
    }
  }
  await f.tick(5010);
  assert.equal(await result, false); assert.equal(f.closed(), false);
  assert.equal(f.requests[0].destroyed, false); noSuccess(f); expectBody(f, av(0, 125));
  assert.ok(f.logs.some((line) => /matched=12 .*freezeWait=400 .*boundary=same-idr/.test(line)));
  f.client.close();
}

async function frozenFixture() {
  const f = await relayFixture();
  const result = f.client.renew(f.target);
  f.requests[1].data([...prefix, ...av(80, 85, 700000000)]);
  f.requests[0].data(av(101, 113)); // Same callback has pre-boundary P frames, IDR, audio, and later P frames.
  await flush();
  assert.equal(f.client.lastTimestamp, 10910);
  assert.equal(f.client.mediaHistory.tailRaw, 10910);
  assert.ok(f.client.heldBytes > 0);
  expectBody(f, av(0, 109));
  return { ...f, result };
}
// Silence timeout, candidate EOF/error/status/codec/IDR mismatch/PTS violation all replay EXACT old data.
for (const failure of ['timeout', 'late-timer', 'end', 'request-error', 'status', 'codec-id', 'different-idr', 'missing-idr', 'pts']) {
  const f = await frozenFixture();
  if (failure === 'timeout') await f.tick(400);
  if (failure === 'late-timer') { f.jumpWithoutTimers(401); f.requests[1].data(av(86, 113, 700000000)); }
  if (failure === 'end') f.requests[1].emit('dataEnd');
  if (failure === 'request-error') f.requests[1].rejectRequest(new Error('fixture request error'));
  if (failure === 'status') f.requests[1].resolveRequest(403);
  if (failure === 'codec-id') f.requests[1].data([tag(8, 0, [0xbf, 0, 0x12, 0x10])]);
  if (failure === 'different-idr' || failure === 'missing-idr') {
    f.requests[1].data([...av(86, 109, 700000000), video(failure === 'different-idr' ? 999 : 110, 700011000, failure !== 'missing-idr')]);
  }
  if (failure === 'pts') f.requests[1].data([...av(86, 110, 700000000), video(111, 700011100, false, -300)]);
  await flush();
  assert.equal(await f.result, false, failure); assert.equal(f.closed(), false, failure);
  assert.equal(f.requests[0].destroyed, false); assert.equal(f.requests[1].destroyed, true);
  assert.equal(f.client.heldBytes, 0); noSuccess(f);
  f.requests[0].data(av(114, 115)); await flush(); expectBody(f, av(0, 115));
  assert.ok(f.logs.some((line) => /matched=12 .*heldBytes=[1-9]\d* boundary=same-idr/.test(line)));
  f.client.close(); assert.equal(f.timers.size, 0);
}
// Measured on device: a candidate can present a refreshed encoder config (49 vs 50 bytes on a 2K60
// Douyu line) after the old stream is already frozen. Identity is the packet proof plus a
// byte-identical boundary IDR, so the splice still completes and the candidate own config travels to
// the decoder ahead of the boundary IDR.
{
  const f = await frozenFixture();
  const drift = tag(9, 0, [0x17, 0, 0, 0, 0, 1, 100, 0, 31, 0xff, 0xe2, 0, 2, 0x67, 100, 1, 0, 1, 0x68]);
  f.requests[1].data([drift]);
  f.requests[1].data(av(86, 113, 700000000));
  await flush();
  assert.equal(await f.result, true, 'config drift alone must not abandon the splice');
  assert.equal(f.client.heldBytes, 0);
  assert.equal(f.requests[1].destroyed, false);
  assert.equal(f.requests[0].destroyed, true);
  assert.ok(f.logs.some((line) => /boundary=same-idr boundaryOutput=11000/.test(line)));
  f.client.close(); assert.equal(f.timers.size, 0);
}
// Byte, descriptor-count, and media-duration limits roll back before retaining the over-limit tag.
for (const limit of ['bytes', 'frames', 'duration']) {
  const f = await frozenFixture();
  const more = limit === 'bytes' ? [tag(18, 0, new Array(512 * 1024).fill(7))] :
    limit === 'frames' ? Array.from({ length: 520 }, () => tag(18, 0, [7])) : av(114, 115);
  f.requests[0].data(more); await flush();
  assert.equal(await f.result, false); assert.equal(f.closed(), false); noSuccess(f);
  expectBody(f, [...av(0, 113), ...more]); assert.equal(f.client.heldBytes, 0);
  f.client.close();
}
// Downstream close while still reversible cancels both deadlines and releases every held frame.
{
  const f = await frozenFixture(); const before = f.body();
  f.conn.emit('close'); await flush();
  assert.equal(await f.result, false); assert.equal(f.client.heldBytes, 0); assert.equal(f.timers.size, 0);
  f.requests[0].data(av(114, 115)); f.requests[1].data(av(86, 115, 700000000)); await flush();
  assert.deepEqual(f.body(), before); noSuccess(f);
}
// Old EOF includes replay in its drain snapshot; candidate EOF after a commit cannot claim success.
{
  const f = await frozenFixture();
  f.block(); f.requests[0].emit('dataEnd'); await flush();
  assert.equal(await f.result, false); assert.equal(f.closed(), false);
  f.unblock(); await flush(); assert.equal(f.closed(), true); expectBody(f, av(0, 113)); noSuccess(f);
}
// Superseding a frozen attempt replays first, then proves a fresh boundary; late callbacks are inert.
{
  const f = await frozenFixture();
  const second = f.client.renew(f.target);
  assert.equal(await f.result, false); await flush(); expectBody(f, av(0, 113));
  f.requests[1].data(av(86, 140, 700000000)); f.requests[1].emit('dataEnd');
  f.requests[2].data([...prefix, ...av(100, 105, 1900000000)]);
  f.requests[0].data(av(114, 122));
  assert.equal(f.client.mediaHistory.tailRaw, 11910);
  f.requests[2].data(av(106, 122, 1900000000)); await flush();
  assert.equal(await second, true); expectBody(f, av(0, 122));
  f.client.close();
}
// A failed rollback while superseding cannot create a new request on the now-closed connection.
{
  const f = await frozenFixture(); f.client.queuedBytes = 8 * 1024 * 1024;
  assert.equal(await f.client.renew(f.target), false); assert.equal(await f.result, false);
  assert.equal(f.closed(), true); assert.equal(f.requests.length, 2); assert.equal(f.timers.size, 0); noSuccess(f);
}
// The result waits for actual queued-send acknowledgement, including prior queued-write failures.
for (const failure of ['send', 'queue-limit', 'commit-timeout', 'candidate-end', 'closed', 'success']) {
  const f = await frozenFixture();
  f.block();
  if (failure === 'queue-limit') f.client.queuedBytes = 8 * 1024 * 1024;
  let resolved: boolean | undefined;
  f.result.then((value: boolean) => { resolved = value; });
  f.requests[1].data(av(86, 113, 700000000)); await flush();
  if (failure !== 'queue-limit') {
    assert.equal(resolved, undefined, 'no eager success before first send completes');
    assert.equal(await f.client.renew(f.target), false, 'cannot supersede an irreversible output commit');
  }
  if (failure === 'send') { f.failSend(); f.unblock(); }
  if (failure === 'commit-timeout') await f.tick(400);
  if (failure === 'candidate-end') f.requests[1].emit('dataEnd');
  if (failure === 'closed') f.conn.emit('close');
  if (failure === 'success') { await f.tick(200); f.unblock(); }
  await flush();
  assert.equal(await f.result, failure === 'success', failure);
  if (failure === 'success') { expectBody(f, av(0, 113)); f.client.close(); }
  else { assert.equal(f.closed(), true); noSuccess(f); }
  assert.equal(f.client.heldBytes, 0); assert.equal(f.timers.size, 0);
  assert.equal(f.requests[0].destroyed, true); assert.equal(f.requests[1].destroyed, true);
}
// Prior old send rejects after the candidate has aligned; still false, never a claimed handoff.
{
  const f = await relayFixture(); f.block();
  const result = f.client.renew(f.target);
  f.requests[1].data([...prefix, ...av(80, 85)]);
  f.requests[0].data(av(101, 113)); await flush();
  f.requests[1].data(av(86, 113)); f.failSend(); f.unblock(); await flush();
  assert.equal(await result, false); assert.equal(f.closed(), true); noSuccess(f);
}
// Ordinary attempt deadline waits out one full GOP (4167ms measured) without freezing old output.
{
  const f = await relayFixture(); const result = f.client.renew(f.target);
  f.requests[1].data([...prefix, ...av(120, 130)]);
  f.requests[0].data(av(101, 125)); await flush(); expectBody(f, av(0, 125));
  await f.tick(8000); assert.equal(await result, false); assert.equal(f.closed(), false); noSuccess(f);
  f.client.close();
}
// Retained 30-second low-sensitivity timeline diagnostics (including scalar raw/output spans).
{
  const f = await relayFixture();
  f.jumpWithoutTimers(30000); f.requests[0].data(av(101, 110)); await flush();
  assert.ok(f.logs.some((line) => /timeline window videoFrames=\d+ videoRawMs=\d+ videoOutputMs=\d+ videoTimingDistortions=\d+ videoMaxStepErrorMs=\d+ audioFrames=\d+ audioRawMs=\d+ audioOutputMs=\d+ audioTimingDistortions=\d+ audioMaxStepErrorMs=\d+ epoch=\d+ queuedBytes=\d+/.test(line)));
  f.client.close();
}
// Health excludes an ended/draining source and a silent source, rather than treating any socket as usable.
{
  const f = await frozenFixture();
  assert.equal(f.relay.canKeepCurrentStream, true);
  await f.tick(400); assert.equal(await f.result, false);
  assert.equal(f.relay.canKeepCurrentStream, true, 'rollback is not handoff success, but old output is usable');
  await f.tick(1000); assert.equal(f.relay.canKeepCurrentStream, false, 'recent upstream input required');
  f.requests[0].data(av(114, 115)); await flush(); assert.equal(f.relay.canKeepCurrentStream, true);
  f.block(); f.requests[0].data(av(116, 117)); f.requests[0].emit('dataEnd');
  assert.equal(f.relay.canKeepCurrentStream, false, 'EOF is unhealthy even while send queue drains');
  f.unblock(); await flush(); f.client.close();
}

// Actual RoomModel expiry callback + retry timer, with transport/player dependencies mocked.
// No native player and no network: verifies integration decisions, not decoder continuity.
const roomPath = fileURLToPath(new URL('../../../entry/src/main/ets/room/RoomModel.ets', import.meta.url));
const roomCompiled = await build({
  stdin: { contents: readFileSync(roomPath, 'utf8').replace(/@(?:ObservedV2|Trace|Computed)\b/g, ''), resolveDir: dirname(roomPath), loader: 'ts' },
  bundle: true, platform: 'node', format: 'cjs', write: false,
  plugins: [{ name: 'offline-room-fixture', setup(build: any) {
    build.onResolve({ filter: /^\.\./ }, () => ({ path: 'room-dependencies', namespace: 'fixture' }));
    build.onLoad({ filter: /.*/, namespace: 'fixture' }, () => ({ contents: `
      export const Sites = fixture.Sites; export const LivePlayer = fixture.LivePlayer;
      export const createLivePlayer = () => new fixture.LivePlayer();
      export const PlayState = { Error: 5, Playing: 2, Buffering: 3 };
      export const Settings = { inst: { autoSwitchLine: true } };
      export const Log = fixture.Log; export const FollowStore = {}; export const HistoryStore = {};
      export class DouyuStreamRelay {} export class SuperChatMessage {} export const LiveMessageType = {};
    ` }));
  } }]
});
function roomFixture(results: Array<boolean | Promise<boolean>> = [false, true], healthy = true, lookupDelay = 0) {
  let now = 0, id = 0, renewals = 0, resets = 0, lookups = 0;
  const timers = new Map<number, { fn: () => void; at: number }>();
  const logs: string[] = [];
  const at = (fn: () => void, ms: number) => { timers.set(++id, { fn, at: now + ms }); return id; };
  const fresh = { urls: ['https://unused.invalid/new?expire=60'], headers: {} };
  const site = { getPlayUrls: async () => {
    lookups++;
    if (lookupDelay) await new Promise<void>((resolve) => at(resolve, lookupDelay));
    return fresh;
  }, getRoomDetail: () => new Promise(() => {}) };
  const module = { exports: {} as any };
  runInNewContext(roomCompiled.outputFiles[0].text, { module, exports: module.exports, Promise, Date: { now: () => now },
    setTimeout: at, clearTimeout: (n: number) => timers.delete(n),
    fixture: { Sites: { of: () => site }, LivePlayer: class {
      wantsPlayback = true; state = 2; stop() {} release() {} resume() {} giveUp() {}
    }, Log: { i: (_: string, text: string) => logs.push(text), w: (_: string, text: string) => logs.push(text) } }
  });
  const model = new module.exports.RoomModel();
  const relay = { canKeepCurrentStream: healthy, dispose() {}, renew: async () => results[renewals++] ?? false };
  model.siteId = 'douyu'; model.detail = {}; model.qualities = [{}]; model.relay = relay;
  model.playQuality = async () => { resets++; model.playSeq++; };
  model.scheduleExpiryRefresh(['https://unused.invalid/old?expire=60'], model.seq);
  const tick = async (until: number) => {
    for (;;) {
      const first = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
      if (!first || first[1].at > until) break;
      now = Math.max(now, first[1].at); timers.delete(first[0]); first[1].fn(); await flush();
    }
    now = Math.max(now, until); await flush();
  };
  return { model, relay, timers, logs, tick, jump: (value: number) => { now = value; },
    stats: () => ({ renewals, resets, lookups }) };
}
for (const second of [true, false]) {
  const f = roomFixture([false, second]);
  await f.tick(30100);
  assert.deepEqual(f.stats(), { renewals: 1, resets: 0, lookups: 1 }, 'healthy rollback does not immediately reset');
  assert.equal(f.model.expiryDue, true);
  assert.match(f.logs.at(-1)!, /retained old stream; retry=1 delayMs=200 .*no seamless claim/);
  await f.tick(30400);
  assert.deepEqual(f.stats(), { renewals: 2, resets: second ? 0 : 1, lookups: 2 },
    'the retry signs its own address: a signed address admits exactly one upstream connection');
  if (second) {
    assert.equal(f.model.expiryDue, false);
    assert.equal([...f.timers.values()][0].at, 60200, 'retry latency does not extend the re-signed TTL');
  }
  f.model.dispose(); assert.equal(f.timers.size, 0);
}
// Acquisition/startup delay and absolute Unix expiries both use the real cutoff, not the refresh time.
{
  const f = roomFixture([true]);
  f.model.scheduleExpiryRefresh(['https://unused.invalid/old?expire=60'], f.model.seq, -5000);
  assert.equal([...f.timers.values()][0].at, 25000);
  await f.tick(25000); assert.equal(f.stats().renewals, 1); f.model.dispose();
  const absolute = roomFixture([true]);
  absolute.jump(1800000000000);
  absolute.model.scheduleExpiryRefresh(['https://unused.invalid/old?expire=1800000060'], absolute.model.seq);
  assert.equal([...absolute.timers.values()][0].at, 1800000030000);
  absolute.model.dispose();
}
// 'unhealthy': the attempt runs but the old stream cannot be retained, so no retry is scheduled.
// 'budget': the delayed lookup leaves less than one attempt window, so no handoff is attempted at
// all and the source is reset before its cutoff rather than starting one that cannot finish.
for (const reason of ['unhealthy', 'budget']) {
  const f = roomFixture([false, false], reason !== 'unhealthy', reason === 'budget' ? 24000 : 0);
  await f.tick(54000);
  assert.deepEqual(f.stats(), { renewals: reason === 'budget' ? 0 : 1, resets: 1, lookups: 1 }, reason);
  assert.equal(f.timers.size, 0, 'no unbounded retention after failed renewal');
  f.model.dispose();
}
for (const action of ['dispose', 'room-change', 'quality-change', 'pause', 'lost-old', 'delayed-retry']) {
  const f = roomFixture(); await f.tick(30100);
  if (action === 'dispose') f.model.dispose();
  if (action === 'room-change') void f.model.open('douyu', 'different-room', null);
  if (action === 'quality-change') f.model.playSeq++;
  if (action === 'pause') f.model.player.wantsPlayback = false;
  if (action === 'lost-old') f.relay.canKeepCurrentStream = false;
  if (action === 'delayed-retry') f.jump(54000);
  await f.tick(30400);
  assert.equal(f.stats().renewals, 1, action);
  assert.equal(f.stats().resets, action === 'lost-old' || action === 'delayed-retry' ? 1 : 0, action);
  if (action === 'pause') assert.equal(f.model.expiryDue, true);
  f.model.dispose(); assert.equal(f.timers.size, 0);
}
// Cancellation while the second renewal promise is in flight cannot re-arm expiry or reset a new source.
for (const action of ['dispose', 'generation', 'relay-replaced']) {
  let release: (value: boolean) => void = () => {};
  const pending = new Promise<boolean>((resolve) => { release = resolve; });
  const f = roomFixture([false, pending]); await f.tick(40200);
  assert.equal(f.stats().renewals, 2);
  if (action === 'dispose') f.model.dispose();
  if (action === 'generation') f.model.playSeq++;
  if (action === 'relay-replaced') f.model.relay = { dispose() {} };
  release(true); await flush();
  assert.equal(f.timers.size, 0, action); assert.equal(f.stats().resets, 0, action);
  f.model.dispose();
}
console.log('FLV handoff: same-IDR 400ms barrier, 6+6 proof, exact bytes/DTS/CTS, fixed 50/200ms lag, rollback/limits/EOF/renew/send failures, timing diagnostics and RoomModel bounded retry passed (offline, not decoder/device validation)');
