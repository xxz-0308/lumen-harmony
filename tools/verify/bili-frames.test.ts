import assert from 'node:assert/strict';
import { deflateSync, inflateSync } from 'node:zlib';
import { BiliDanmaku } from '../../entry/src/main/ets/core/danmaku/BiliDanmaku';
import { ByteWriter, Utf8 } from '../../entry/src/main/ets/core/common/Bytes';
import { Platform } from '../../entry/src/main/ets/core/common/Transport';
import { LiveMessage } from '../../entry/src/main/ets/core/model/Models';

class Decoder extends BiliDanmaku {
  feed(bytes: Uint8Array): void { this.decode(bytes); }
}
const packet = (body: Uint8Array, version = 1, operation = 5): Uint8Array => {
  const writer = new ByteWriter();
  writer.u32(body.length + 16); writer.u16(16); writer.u16(version);
  writer.u32(operation); writer.u32(1); writer.bytes(body);
  return writer.toBytes();
};
const join = (...frames: Uint8Array[]): Uint8Array => {
  const writer = new ByteWriter();
  frames.forEach((frame) => writer.bytes(frame));
  return writer.toBytes();
};
const chat = packet(Utf8.encode(JSON.stringify({ cmd: 'DANMU_MSG:4:0:2:2:2:0',
  info: [[0, 0, 0, 0xffeedd], 'fixture message', [1, 'fixture user']] })));
const sc = packet(Utf8.encode(JSON.stringify({ cmd: 'SUPER_CHAT_MESSAGE', data: {
  user_info: { uname: 'fixture supporter', face: 'https://example.test/avatar.jpg' },
  message: 'fixture paid message', price: 30, start_time: 1000, end_time: 1060,
  background_color: '#EDF5FF', background_bottom_color: '#2A60B2'
} })));
Platform.inflater = { inflate: (bytes) => new Uint8Array(inflateSync(bytes)) };
const decoder = new Decoder();
const messages: LiveMessage[] = [];
decoder.onMessage = (message) => messages.push(message);
decoder.feed(packet(new Uint8Array(deflateSync(join(chat, sc))), 2));
assert.equal(messages.length, 2);
assert.equal(messages[0].text, 'fixture message');
assert.equal(messages[0].color, 0xffeedd);
assert.equal(messages[1].superChat?.price, 30);
assert.equal(messages[1].superChat?.endTime, 1060);
assert.equal(messages[1].superChat?.userName, 'fixture supporter');

// The client negotiates zlib (protover=2), not brotli. An unrequested version must
// neither be parsed as JSON nor prevent a following valid packet being decoded.
decoder.feed(join(packet(new Uint8Array([1, 2, 3]), 3), chat));
assert.equal(messages.length, 3);
assert.equal(messages[2].text, 'fixture message');
const count = new ByteWriter(); count.u32(42);
decoder.feed(packet(count.toBytes(), 1, 3));
assert.equal(messages[3].online, 42);
const before = messages.length;
decoder.feed(new Uint8Array(16));
decoder.feed(chat.slice(0, chat.length - 1));
assert.equal(messages.length, before, 'zero-size and truncated packets cannot emit fabricated messages');
decoder.feed(chat);
assert.equal(messages.length, before + 1, 'a later valid packet still decodes');
console.log('Bili frames: zlib batch, chat variants, super-chat fixture, unsupported version skip and malformed boundaries passed (no brotli support claimed)');
