import assert from 'node:assert/strict';
import { DouyuDanmaku } from '../../entry/src/main/ets/core/danmaku/DouyuDanmaku';
import { LiveMessageType } from '../../entry/src/main/ets/core/model/Models';
import { Utf8 } from '../../entry/src/main/ets/core/common/Bytes';
import { Platform, WsConnection, WsListener, TimerHost } from '../../entry/src/main/ets/core/common/Transport';

class FakeClock implements TimerHost {
  now = 0;
  id = 0;
  jobs: Map<number, { at: number; period: number; fn: () => void }> = new Map();
  setInterval(fn: () => void, ms: number): number { return this.add(fn, ms, ms); }
  setTimeout(fn: () => void, ms: number): number { return this.add(fn, ms, 0); }
  clearInterval(id: number): void { this.jobs.delete(id); }
  clearTimeout(id: number): void { this.jobs.delete(id); }
  private add(fn: () => void, ms: number, period: number): number {
    const id = ++this.id;
    this.jobs.set(id, { at: this.now + ms, period, fn });
    return id;
  }
  advance(ms: number): void {
    const end = this.now + ms;
    while (true) {
      let first = 0;
      let at = end + 1;
      for (const [id, job] of this.jobs) {
        if (job.at < at) { first = id; at = job.at; }
      }
      if (!first || at > end) break;
      this.now = at;
      const job = this.jobs.get(first);
      if (!job) continue;
      if (job.period) job.at += job.period;
      else this.jobs.delete(first);
      job.fn();
    }
    this.now = end;
  }
}
class FakeSocket implements WsConnection {
  listener: WsListener;
  closed = false;
  sent: Uint8Array[] = [];
  constructor(listener: WsListener) { this.listener = listener; }
  sendBinary(data: Uint8Array): void { this.sent.push(data); }
  sendText(text: string): void {}
  close(): void { this.closed = true; }
}
const clock = new FakeClock();
const sockets: FakeSocket[] = [];
Platform.ws = { connect: (_url: string, _headers: Record<string, string>, listener: WsListener): WsConnection => {
  const socket = new FakeSocket(listener);
  sockets.push(socket);
  return socket;
} };
Platform.timers = clock;
Platform.log = () => {};
const client = new DouyuDanmaku();
const statuses: string[] = [];
let ready = 0;
client.onReady = () => { ready++; };
client.onStatus = (s: string) => statuses.push(s);
client.start('9999');
sockets[0].listener.onOpen();
assert.equal(ready, 0, 'socket open is not a Douyu login confirmation');
assert.equal(sockets[0].sent.length, 1, 'open only sends login: an asynchronous sender must not race join ahead of authentication');
assert.match(Utf8.decode(sockets[0].sent[0]), /type@=loginreq\/roomid@=9999\//);
sockets[0].listener.onBinary(DouyuDanmaku.pack('type@=loginres/error@=1/'));
assert.equal(sockets[0].sent.length, 1, 'failed login cannot join the group');
assert.equal(ready, 0, 'failed login is not connected');
sockets[0].listener.onBinary(DouyuDanmaku.pack('type@=loginres/error@=0/'));
assert.equal(ready, 1, 'successful login requests the chat group and marks readiness');
assert.equal(sockets[0].sent.length, 2, 'group is sent only after the successful login response');
assert.match(Utf8.decode(sockets[0].sent[1]), /type@=joingroup\/rid@=9999\/gid@=-9999\//);
sockets[0].listener.onBinary(DouyuDanmaku.pack('type@=loginres/error@=0/'));
assert.equal(sockets[0].sent.length, 2, 'duplicate login responses do not send duplicate joins');
assert.equal(ready, 1);
const texts: string[] = [];
client.onMessage = (msg) => { if (msg.type === LiveMessageType.Chat) texts.push(msg.text); };
const firstChat = DouyuDanmaku.pack('type@=chatmsg/dms@=3/nn@=fixture/txt@=弹幕@S测试@A/col@=2/');
const secondChat = DouyuDanmaku.pack('type@=chatmsg/dms@=3/nn@=fixture/txt@=第二条/');
const batch = new Uint8Array(firstChat.length + secondChat.length);
batch.set(firstChat);
batch.set(secondChat, firstChat.length);
sockets[0].listener.onBinary(batch);
assert.deepEqual(texts, ['弹幕/测试@', '第二条'], 'joined chat packets decode and reach the room callback, including batched frames');
clock.advance(15000);
assert.equal(sockets[0].sent.length, 3, 'heartbeat is sent while the socket is open');
const current = sockets[0];
current.listener.onClose('closed');
clock.advance(1500);
sockets[1].listener.onOpen();
sockets[1].listener.onBinary(DouyuDanmaku.pack('type@=mrkl/'));
sockets[1].listener.onClose('closed again');
assert.equal(statuses.at(-1), '弹幕重连中（2）', 'one packet cannot reset the failure backoff');
clock.advance(3000);
sockets[2].listener.onOpen();
assert.equal(sockets[2].sent.length, 1, 'reconnect resets group state and waits for login again');
sockets[2].listener.onBinary(DouyuDanmaku.pack('type@=loginres/error@=0/'));
assert.equal(sockets[2].sent.length, 2, 'the replacement connection rejoins after authentication');
clock.advance(20000);
sockets[2].listener.onClose('closed after stable interval');
assert.equal(statuses.at(-1), '弹幕重连中（1）', 'a sustained authenticated connection resets backoff');
clock.advance(1500);
sockets[3].listener.onOpen();
clock.advance(10000);
assert.equal(statuses.at(-1), '弹幕重连中（2）', 'a silent unauthenticated socket reconnects');
assert.equal(sockets[3].closed, true);
client.stop();
console.log('Danmaku: join, login confirmation, heartbeat, repeated drops, auth timeout and cleanup');
