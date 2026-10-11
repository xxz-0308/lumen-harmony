import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';
import { build } from 'esbuild';
import { LiveMessage, LiveMessageType } from '../../entry/src/main/ets/core/model/Models';

// Exercise the actual RoomModel with only transport/player dependencies replaced.
const path = fileURLToPath(new URL('../../../entry/src/main/ets/room/RoomModel.ets', import.meta.url));
const compiled = await build({
  stdin: { contents: readFileSync(path, 'utf8').replace(/@(?:ObservedV2|Trace|Computed)\b/g, ''), resolveDir: dirname(path), loader: 'ts' },
  bundle: true, platform: 'node', format: 'cjs', write: false,
  plugins: [{ name: 'chat-history-dependencies', setup(b: any) {
    b.onResolve({ filter: /^\.\./ }, () => ({ path: 'dependencies', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, () => ({ contents: `
      export const Sites = { of: () => ({ getRoomDetail: () => new Promise(() => {}) }) };
      export const createLivePlayer = () => ({ stop() {}, release() {} });
      export const PlayState = { Error: 5, Playing: 2, Buffering: 3 };
      export const Settings = { inst: { showSuperChat: true } };
      export const Log = { i() {}, w() {} }; export const FollowStore = {}; export const HistoryStore = {};
      export class DouyuStreamRelay {} export class SuperChatMessage {}
      export const LiveMessageType = fixture.LiveMessageType;
    ` }));
  } }]
});
function fixture() {
  let now = 0, id = 0, bulletCount = 0;
  const timers = new Map<number, { at: number; fn: () => void }>();
  const module = { exports: {} as any };
  runInNewContext(compiled.outputFiles[0].text, {
    module, exports: module.exports, Promise, Date: { now: () => now }, fixture: { LiveMessageType },
    setTimeout: (fn: () => void, ms: number) => { timers.set(++id, { at: now + ms, fn }); return id; },
    clearTimeout: (n: number) => timers.delete(n)
  });
  const model = new module.exports.RoomModel();
  model.isBlocked = (text: string) => text === 'blocked';
  model.onBullet = () => bulletCount++;
  const tick = (ms: number) => {
    const until = now + ms;
    for (;;) {
      const first = [...timers].sort((a,b) => a[1].at-b[1].at)[0];
      if (!first || first[1].at > until) break;
      now = first[1].at; timers.delete(first[0]); first[1].fn();
    }
    now = until;
  };
  const send = (n: number) => model.onMessage(LiveMessage.chat('fixture user', `full message ${n} 🎮`, n));
  return { model, timers, tick, send, bullets: () => bulletCount };
}
{
  const f = fixture();
  f.send(0); const before = f.model.chats;
  f.tick(199); assert.equal(f.model.chats, before, 'visible chat keeps the existing 200ms batch delay');
  f.tick(1); assert.equal(f.model.chats.length, 1); assert.equal(f.model.chatCount, 1);
  for (let n=1; n<1001; n++) f.send(n);
  assert.equal(f.timers.size, 1, 'a burst owns only one publication timer');
  assert.equal(f.model.retainedChats.length, 300, 'in-flight bursts are bounded before publication');
  f.tick(200);
  assert.deepEqual(Array.from(f.model.chats, (c:any)=>c.text), Array.from({length:300}, (_,i)=>`full message ${i+701} 🎮`));
  assert.equal(f.model.chatCount, 1001); assert.equal(f.bullets(), 1001, 'history capping never drops flying-bullet delivery');
  const latest = f.model.chats;
  f.model.setChatActive(false); f.model.setChatActive(true);
  assert.equal(f.model.chats, latest, 'activity without new messages does not replace the snapshot');
  f.model.dispose();
}
{
  const f = fixture(); f.model.setChatActive(false); const snapshot = f.model.chats;
  for (let n=0; n<10000; n++) f.send(n);
  assert.equal(f.timers.size, 0, 'hidden history has no presentation timer');
  assert.equal(f.model.chats, snapshot, 'hidden history does not invalidate the traced snapshot');
  assert.equal(f.model.retainedChats.length, 300); assert.equal(f.bullets(), 10000);
  f.model.setChatActive(true);
  assert.deepEqual(Array.from(f.model.chats, (c:any)=>c.text), Array.from({length:300}, (_,i)=>`full message ${i+9700} 🎮`));
  assert.equal(f.model.chatCount, 10000);
  const tail = Array.from(f.model.chats.slice(-14), (c:any)=>c.text);
  assert.deepEqual(tail, Array.from({length:14}, (_,i)=>`full message ${i+9986} 🎮`), 'fullscreen receives the same newest 14 messages');
  f.model.dispose();
}
{
  const f = fixture(); f.send(1); const old = [...f.timers.values()][0].fn;
  f.model.setChatActive(false); f.send(2); f.model.setChatActive(true); f.send(3);
  const current = f.model.chats; old();
  assert.equal(f.model.chats, current, 'a cancelled callback cannot publish a newer batch early');
  assert.equal(f.timers.size, 1); f.tick(200); assert.equal(f.model.chats.length, 3);
  f.send(4); const retired = [...f.timers.values()][0].fn;
  void f.model.open('huya', 'other-room', null);
  assert.equal(f.model.chats.length, 0); assert.equal(f.model.chatCount, 0);
  f.send(5); retired(); assert.equal(f.model.chats.length, 0, 'room changes invalidate old publication callbacks');
  f.tick(200); assert.equal(f.model.chats[0].text, 'full message 5 🎮');
  f.send(6); f.model.dispose(); f.tick(200); f.send(7); f.model.setChatActive(true);
  assert.equal(f.timers.size, 0); assert.equal(f.model.retainedChats.length, 0);
}
{
  const f = fixture(); f.model.setChatActive(false);
  const online = new LiveMessage(); online.type = LiveMessageType.Online; online.online = 123;
  f.model.onMessage(online); assert.equal(f.model.online, 123);
  f.model.onMessage(LiveMessage.chat('fixture', 'blocked', 0xffffff)); f.tick(300);
  assert.equal(f.model.blockedChats, 1); assert.equal(f.bullets(), 0); assert.equal(f.model.retainedChats.length, 0);
  f.model.dispose();
}
console.log('Chat history: bounded bursts, 200ms visible batching, hidden zero-publication, latest-tail restore, progress and stale/disposed callbacks passed');
