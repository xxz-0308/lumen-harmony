import assert from 'node:assert/strict';
import { FlvTimestampNormalizer } from '../../entry/src/main/ets/player/FlvTimestampNormalizer';

const header = new Uint8Array([70, 76, 86, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0]);

function tag(type: number, time: number, payload: number[]): Uint8Array {
  const out = new Uint8Array(15 + payload.length);
  out[0] = type;
  out[1] = (payload.length >>> 16) & 255;
  out[2] = (payload.length >>> 8) & 255;
  out[3] = payload.length & 255;
  out[4] = (time >>> 16) & 255;
  out[5] = (time >>> 8) & 255;
  out[6] = time & 255;
  out[7] = (time >>> 24) & 255;
  out.set(payload, 11);
  const prev = payload.length + 11;
  out.set([(prev >>> 24) & 255, (prev >>> 16) & 255, (prev >>> 8) & 255, prev & 255], 11 + payload.length);
  return out;
}

function join(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

function times(data: Uint8Array): number[] {
  const result: number[] = [];
  let pos = 13;
  while (pos < data.length) {
    const size = data[pos + 1] * 65536 + data[pos + 2] * 256 + data[pos + 3];
    result.push((data[pos + 4] * 65536 + data[pos + 5] * 256 + data[pos + 6] + data[pos + 7] * 16777216) >>> 0);
    pos += size + 15;
  }
  return result;
}

function normalize(parts: Uint8Array[]): Uint8Array {
  const normalizer = new FlvTimestampNormalizer();
  return join(parts.flatMap((part) => normalizer.push(part)));
}

const source = join([
  header,
  tag(18, 404661691, [2, 0, 5, 104, 101, 108, 108, 111]),
  tag(9, 404661691, [0x17, 0, 0, 0, 0, 1, 100]),
  tag(8, 404661691, [0xaf, 0, 0x12, 0x10]),
  tag(9, 495502391, [0x17, 1, 0, 0, 0, 9, 8, 7]),
  tag(8, 495502431, [0xaf, 1, 11, 22, 33]),
  tag(18, 495502451, [1, 2, 3]),
  tag(9, 495502491, [0x27, 1, 0, 0, 0, 6]),
  tag(9, 495502511, [0x17, 0, 0, 0, 0, 1]),
  tag(9, 495522491, [0x17, 1, 0, 0, 0, 5])
]);
// Script and mid-stream sequence-header tags reuse the last media timestamp so they never lead the timeline.
const expected = [0, 0, 0, 0, 40, 40, 100, 100, 20100];
const fixed = normalize([source]);
assert.deepEqual(times(fixed), expected);
for (let i = 0; i < source.length; i++) {
  // Only the four timestamp bytes of each tag are allowed to change.
  const isTimestamp = (() => {
    let pos = 13;
    while (pos < source.length) {
      const size = source[pos + 1] * 65536 + source[pos + 2] * 256 + source[pos + 3];
      if (i >= pos + 4 && i < pos + 8) return true;
      pos += size + 15;
    }
    return false;
  })();
  if (!isTimestamp) assert.equal(fixed[i], source[i], `byte ${i}`);
}
for (let split = 1; split < source.length; split++) {
  assert.deepEqual(normalize([source.slice(0, split), source.slice(split)]), fixed, `split ${split}`);
}
for (const chunkSize of [1, 2, 3, 7, 11, 16, 127]) {
  const chunks: Uint8Array[] = [];
  for (let i = 0; i < source.length; i += chunkSize) chunks.push(source.slice(i, i + chunkSize));
  assert.deepEqual(normalize(chunks), fixed, `chunk ${chunkSize}`);
}

const longTags: Uint8Array[] = [];
for (let i = 0; i <= 40; i++) {
  longTags.push(tag(9, 500000 + i * 10000, [0x17, 1, 0, 0, 0, i]));
}
assert.equal(times(normalize([join([header, ...longTags])])).at(-1), 400000);

const extended = join([new Uint8Array([70, 76, 86, 1, 5, 0, 0, 0, 12, 42, 43, 44, 0, 0, 0, 0]),
  tag(8, 0xffffff00, [0xaf, 1, 1]), tag(9, 0x100, [0x17, 1, 1]),
  tag(9, 0x0f0, [0x17, 1, 2]), tag(9, 500000, [0x17, 1, 3]), tag(9, 500040, [0x17, 1, 4])]);
const wrapped = normalize([extended]);
assert.deepEqual(times(join([header, wrapped.slice(16)])), [0, 512, 512, 513, 553]);
assert.deepEqual([...wrapped.slice(0, 16)], [...extended.slice(0, 16)]);
assert.throws(() => normalize([new Uint8Array([70, 76, 88, 1, 5, 0, 0, 0, 9])]), /FLV/);
const invalid = join([header, tag(9, 1, [0x17, 1])]);
invalid[invalid.length - 1] = 0;
assert.throws(() => normalize([invalid]), /previous tag size/);
const oversized = join([header, new Uint8Array([9, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0])]);
assert.throws(() => normalize([oversized]), /size limit/);
// A script tag stamped ahead of the media must not pull later media timestamps backwards.
const ahead = normalize([join([
  header,
  tag(9, 1000, [0x17, 1, 0, 0, 0, 1]),
  tag(18, 5000, [1, 2, 3]),
  tag(9, 1040, [0x27, 1, 0, 0, 0, 2])
])]);
const aheadTimes = times(ahead);
assert.deepEqual(aheadTimes, [0, 0, 40]);
for (let i = 1; i < aheadTimes.length; i++) assert.ok(aheadTimes[i] >= aheadTimes[i - 1]);
// Isolated reorder events are not a consecutive backwards run.
assert.deepEqual(times(normalize([join([header,
  tag(9, 1000, [0x17, 1, 1]), tag(8, 990, [0xaf, 1, 2]),
  tag(9, 1040, [0x27, 1, 3]), tag(8, 1030, [0xaf, 1, 4]),
  tag(9, 1080, [0x27, 1, 5])])])), [0, 0, 40, 40, 80]);
// Non-media tags neither trigger nor consume a media resync.
assert.deepEqual(times(normalize([join([header,
  tag(9, 1000, [0x17, 1, 1]), tag(18, 990, [1]),
  tag(9, 990, [0x27, 1, 2]), tag(9, 1040, [0x27, 1, 3])])])), [0, 0, 0, 40]);
assert.deepEqual(times(normalize([join([header,
  tag(9, 1000, [0x17, 1, 1]), tag(9, 900, [0x27, 1, 2]),
  tag(18, 0, [1]), tag(9, 920, [0x27, 1, 3]),
  tag(9, 960, [0x27, 1, 4])])])), [0, 0, 0, 1, 41]);
// Non-handoff path also preserves repeated content while concealing raw timestamp rollback.
const repeatedRaw = [10000, 8000, 8040, 8080];
const repeated = normalize([join([header, ...repeatedRaw.map((raw, id) =>
  tag(9, raw, [id === 1 ? 0x17 : 0x27, 1, 0, 0, 0, id]))])]);
assert.deepEqual(times(repeated), [0, 0, 1, 41]);
const contentTimes: number[] = [];
for (let pos = 13; pos < repeated.length; pos += 21) {
  contentTimes.push(repeatedRaw[repeated[pos + 16]]);
}
assert.deepEqual(contentTimes, [10000, 8000, 8040, 8080],
  'unchanged fixture content identities reveal rewind independently of output timestamps');
assert.equal(contentTimes[0] - contentTimes[1], 2000,
  'KNOWN LIMITATION: timestamp normalization is not content deduplication');
// Preserve the legacy decoder output policy explicitly: cross-track arrival reorder is still
// NOT per-track DTS preservation. Handoff proof observes raw DTS instead of treating this as
// common-clock evidence; changing AVPlayer's timestamp policy needs separate device validation.
const crossTrackRaw = [1000, 970, 991, 1017];
const observedRaw: number[] = [];
const crossTrack = new FlvTimestampNormalizer().push(join([header,
  tag(9, 1000, [0x17, 1, 0, 0, 0, 1]), tag(8, 970, [0xaf, 1, 1]),
  tag(8, 991, [0xaf, 1, 2]), tag(9, 1017, [0x27, 1, 0, 0, 0, 2])]),
  (_frame, raw) => observedRaw.push(raw));
assert.deepEqual(observedRaw, crossTrackRaw, 'observer preserves exact input DTS, omitting the FLV header');
assert.deepEqual(times(join(crossTrack)), [0, 0, 1, 27]);
assert.equal(times(join(crossTrack))[2] - times(join(crossTrack))[1], 1,
  'KNOWN LIMITATION: two audio arrivals after a leading video compress 21ms into 1ms');
assert.equal(times(join(crossTrack))[3], 27,
  'KNOWN LIMITATION: cross-track reanchor stretches video 17ms into 27ms');
// Raw descriptors align with every returned frame, including a sentinel for the FLV header.
{
  const p = new FlvTimestampNormalizer();
  const data = join([header, tag(9, 700001000, [0x17, 1, 0, 0, 0, 1]), tag(8, 700001010, [0xaf, 1, 2])]);
  assert.equal(p.push(data.slice(0, 20)).length, 1);
  assert.deepEqual(p.rawTimestamps, [-1]);
  assert.equal(p.push(data.slice(20)).length, 2);
  assert.deepEqual(p.rawTimestamps, [700001000, 700001010]);
  p.push(new Uint8Array(0)); assert.deepEqual(p.rawTimestamps, []);
  const clock = new FlvTimestampNormalizer();
  clock.anchor(700001000, 12340);
  assert.equal(clock.normalizeTimestamp(700001010, true), 12350);
  assert.equal(clock.normalizeTimestamp(900000000, false), 12350, 'metadata cannot move the anchored clock');
  assert.equal(clock.normalizeTimestamp(700001040, true), 12380);
}
console.log('FLV normalizer: fragmentation/wrap/reset, raw descriptors/clock anchor; known single-stream replay and cross-track timing limitations retained');
