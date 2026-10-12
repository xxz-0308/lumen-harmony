import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';
import { build } from 'esbuild';
import { LiveMessage, LiveMessageType, LiveRoomDetail, LiveRoomItem, PlayQuality, PlayUrls } from '../../entry/src/main/ets/core/model/Models';
import { PlayState } from '../../entry/src/main/ets/player/PlayerApi';

// Same offline harness as chat-history: compile the real RoomModel, replace only its dependencies.
const path = fileURLToPath(new URL('../../../entry/src/main/ets/room/RoomModel.ets', import.meta.url));
const source = readFileSync(path, 'utf8');
const compiled = await build({
  stdin: { contents: source.replace(/@(?:ObservedV2|Trace|Computed)\b/g, ''), resolveDir: dirname(path), loader: 'ts' },
  bundle: true, platform: 'node', format: 'cjs', write: false,
  plugins: [{ name: 'room-switch-dependencies', setup(b) {
    b.onResolve({ filter: /^\.\./ }, () => ({ path: 'dependencies', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, () => ({ contents: `
      export const { Sites, createLivePlayer, PlayState, Settings, Log, FollowStore,
        HistoryStore, DouyuStreamRelay, SuperChatMessage, LiveMessageType } = fixture;
    ` }));
  } }]
});

function deferred<T>() {
  let resolve!: (v: T) => void, reject!: (e: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
function detail(id: string, site = 'huya', live = true): LiveRoomDetail {
  const d = new LiveRoomDetail();
  d.siteId = site as any; d.roomId = id; d.title = `title:${id}`; d.userName = `user:${id}`;
  d.status = live; d.online = 100; d.danmakuArgs = { token: 'fixture' } as any;
  return d;
}
function qualities(): PlayQuality[] {
  const low = new PlayQuality(), high = new PlayQuality();
  low.name = '720p'; low.sort = 720; high.name = '1080p'; high.sort = 1080;
  return [low, high];
}
function urls(id: string): PlayUrls {
  const p = new PlayUrls(); p.urls = [`https://test.invalid/${id}.flv?expire=120`];
  p.headers = { 'X-Room': id }; p.qualityIds = [1080]; return p;
}
type Plan = { d: Promise<LiveRoomDetail>; q: Promise<PlayQuality[]>; u: Promise<PlayUrls> };
function fixture() {
  const events: string[] = [], rooms = new Map<string, Plan>();
  const timers = new Map<number, () => void>(); let timerId = 0;
  const relays: any[] = [], chats: any[] = [], history: string[] = [], follows: string[] = [];
  let relayGate: ReturnType<typeof deferred<string[]>> | null = null;
  let nextOpen: ReturnType<typeof deferred<void>> | null = null;
  const player = {
    state: PlayState.Playing, firstFrame: true, wantsPlayback: true, lineIndex: 0,
    notice: '', noticeSeq: 0, autoSwitch: true, onPlaying: null as any,
    onStreamEnded: null as any, onLinesExhausted: null as any, onSuspended: null as any,
    open: async (sources: string[], headers: any, line: number, seamless: boolean, play: boolean) => {
      events.push(`open:${headers['X-Room']}:${play}`); player.wantsPlayback = play;
      player.lineIndex = line; player.state = play ? PlayState.Loading : PlayState.Paused;
      const pending = nextOpen; nextOpen = null; if (pending) await pending.promise;
    },
    stop: () => { events.push('stop'); player.firstFrame = false; player.wantsPlayback = false; },
    release: () => { events.push('release'); player.wantsPlayback = false; },
    selectLine: (i: number) => { events.push(`line:${i}`); player.lineIndex = i; },
    pause: () => { player.wantsPlayback = false; player.state = PlayState.Paused; },
    resume: () => { events.push('resume'); player.wantsPlayback = true; },
    giveUp: (s: string) => { events.push(`giveUp:${s}`); },
  };
  class Relay {
    disposed = false; disposals = 0; registrations: string[][] = [];
    async register(input: string[], _headers: any) {
      this.registrations.push(input.slice()); events.push(`register:${relays.indexOf(this)}`);
      const gate = relayGate; relayGate = null;
      return gate ? await gate.promise : input.map((s) => `relay:${s}`);
    }
    constructor() { relays.push(this); }
    dispose() { this.disposed = true; this.disposals++; events.push(`relayDispose:${relays.indexOf(this)}`); }
  }
  const get = (id: string) => { const p = rooms.get(id); assert.ok(p, `missing plan ${id}`); return p; };
  const site = {
    getRoomDetail: (id: string) => { events.push(`detail:${id}`); return get(id).d; },
    getPlayQualities: (d: LiveRoomDetail) => { events.push(`qualities:${d.roomId}`); return get(d.roomId).q; },
    getPlayUrls: (d: LiveRoomDetail, q: PlayQuality) => { events.push(`urls:${d.roomId}:${q.sort}`); return get(d.roomId).u; },
    getSuperChats: async () => [],
    createDanmaku: () => {
      const dm = { stopped: false, onMessage: null as any, onStatus: null as any, onReady: null as any,
        start() { events.push('chatStart'); }, stop() { dm.stopped = true; events.push('chatStop'); } };
      chats.push(dm); return dm;
    }
  };
  const module = { exports: {} as any };
  runInNewContext(compiled.outputFiles[0].text, {
    module, exports: module.exports, Promise, Date, fixture: {
      Sites: { of: () => site }, createLivePlayer: () => player, PlayState,
      Settings: { inst: { capAt1080: false, autoSwitchLine: true, blockWords: [], showSuperChat: true } },
      Log: { i() {}, w() {} },
      FollowStore: { inst: { updateFromDetail: (d: LiveRoomDetail) => follows.push(d.roomId) } },
      HistoryStore: { inst: { record: (d: LiveRoomDetail) => history.push(d.roomId) } },
      DouyuStreamRelay: Relay, SuperChatMessage: class {}, LiveMessageType,
    },
    setTimeout: (fn: () => void) => { timers.set(++timerId, fn); return timerId; },
    clearTimeout: (id: number) => timers.delete(id),
  });
  const model = new module.exports.RoomModel();
  const plan = (id: string, siteId = 'huya', overrides: Partial<Plan> = {}) => {
    rooms.set(id, { d: Promise.resolve(detail(id, siteId)), q: Promise.resolve(qualities()),
      u: Promise.resolve(urls(id)), ...overrides });
  };
  const openOld = async (siteId = 'huya') => {
    plan('old', siteId); await model.open(siteId, 'old', null);
    player.firstFrame = true; player.state = PlayState.Playing;
    events.length = 0; history.length = 0; follows.length = 0;
  };
  const preview = (id: string) => { const p = new LiveRoomItem(); p.roomId = id; p.title = `preview:${id}`; return p; };
  return { model, player, plan, preview, openOld, events, relays, chats, history, follows, timers,
    deferRelay: () => { relayGate = deferred<string[]>(); return relayGate; },
    deferOpen: () => { nextOpen = deferred<void>(); return nextOpen; } };
}

// Deferred detail, qualities and URLs do not retire or relabel the playing room.
{
  const f = fixture(); await f.openOld();
  const d = deferred<LiveRoomDetail>(), q = deferred<PlayQuality[]>(), u = deferred<PlayUrls>();
  f.plan('target', 'bilibili', { d: d.promise, q: q.promise, u: u.promise });
  const before = f.model.detail, dm = f.chats[0], chatSnapshot = f.model.chats;
  const work = f.model.switchTo('bilibili', 'target', f.preview('target'));
  assert.match(f.player.notice, /正在准备/);
  for (const advance of [() => d.resolve(detail('target', 'bilibili')), () => q.resolve(qualities())]) {
    assert.equal(f.model.detail, before); assert.equal(f.model.siteId, 'huya');
    assert.equal(f.model.roomId, 'old'); assert.equal(f.player.firstFrame, true);
    assert.equal(f.model.switchSeq, 0); assert.equal(dm.stopped, false);
    assert.equal(f.model.chats, chatSnapshot); assert.equal(f.events.includes('stop'), false);
    advance(); await flush();
  }
  assert.equal(f.model.roomId, 'old'); assert.equal(f.history.length, 0);
  u.resolve(urls('target')); await work;
  assert.equal(f.model.roomId, 'target'); assert.equal(f.model.title, 'title:target');
  assert.equal(f.model.siteId, 'bilibili'); assert.equal(f.model.switchSeq, 1);
  assert.equal(f.player.firstFrame, false); assert.equal(dm.stopped, true);
  assert.equal(f.player.notice, ''); assert.equal(f.model.loading, false);
  assert.deepEqual(f.history, ['target']); assert.deepEqual(f.follows, ['target']);
  assert.equal(f.events.filter(s => s === 'stop').length, 1);
  assert.ok(f.events.indexOf('stop') < f.events.indexOf('open:target:true'));
  assert.equal(f.events.filter(s => s.startsWith('urls:target')).length, 1, 'commit does not refetch');
  assert.equal(f.model.qualityIndex, 1); assert.deepEqual(Array.from(f.model.lineQualityIds), [1080]);
  f.model.dispose();
}

// Every failed preparation keeps playback, room labels, chat and bullet generation unchanged.
for (const failure of ['detail', 'qualities', 'empty-quality', 'urls', 'empty-url', 'closed', 'relay']) {
  const f = fixture(); await f.openOld('douyu'); const oldRelay = f.relays[0], oldChat = f.chats[0];
  const gate = deferred<any>(); const overrides: Partial<Plan> = {};
  if (failure === 'detail' || failure === 'closed') overrides.d = gate.promise;
  else if (failure.includes('quality') || failure === 'qualities') overrides.q = gate.promise;
  else if (failure !== 'relay') overrides.u = gate.promise;
  f.plan('bad', failure === 'relay' ? 'douyu' : 'huya', overrides);
  const registration = failure === 'relay' ? f.deferRelay() : null;
  const work = f.model.switchTo(failure === 'relay' ? 'douyu' : 'huya', 'bad', null);
  await flush();
  if (failure === 'closed') gate.resolve(detail('bad', 'huya', false));
  else if (failure === 'empty-quality') gate.resolve([]);
  else if (failure === 'empty-url') { const p = urls('bad'); p.urls = []; gate.resolve(p); }
  else if (registration) registration.reject(new Error('relay unavailable'));
  else gate.reject(new Error(`${failure} unavailable`));
  await work;
  assert.equal(f.model.roomId, 'old', failure); assert.equal(f.model.switchSeq, 0, failure);
  assert.equal(f.player.firstFrame, true, failure); assert.equal(oldChat.stopped, false, failure);
  assert.equal(oldRelay.disposed, false, failure); assert.equal(f.model.error, '', failure);
  assert.match(f.player.notice, /保留当前直播间/, failure); assert.equal(f.history.length, 0);
  if (registration) assert.equal(f.relays[1].disposed, true);
  f.model.dispose();
}

// Latest target wins even when earlier URL resolution finishes last (including late failures).
for (const rejectStale of [false, true]) {
  const f = fixture(); await f.openOld(); const stale = deferred<PlayUrls>();
  f.plan('first', 'huya', { u: stale.promise }); f.plan('second');
  const first = f.model.switchTo('huya', 'first', null); await flush();
  await f.model.switchTo('huya', 'second', null);
  const notice = f.player.notice;
  if (rejectStale) stale.reject(new Error('stale failure')); else stale.resolve(urls('first'));
  await first;
  assert.equal(f.model.roomId, 'second'); assert.equal(f.model.switchSeq, 1);
  assert.equal(f.player.notice, notice); assert.deepEqual(f.history, ['second']);
  assert.equal(f.events.some(s => s.startsWith('open:first:')), false); f.model.dispose();
}

// Explicit current-room actions cancel pending user intent; same quality counts too.
for (const action of ['same-current', 'exit-intent', 'quality', 'refresh', 'line', 'resume', 'open', 'dispose']) {
  const f = fixture(); await f.openOld(); const pending = deferred<PlayUrls>();
  f.plan('target', 'huya', { u: pending.promise });
  const work = f.model.switchTo('huya', 'target', null); await flush();
  if (action === 'same-current') await f.model.switchTo('huya', 'old', null);
  if (action === 'exit-intent') f.model.cancelSwitch();
  if (action === 'quality') await f.model.selectQuality(f.model.qualityIndex);
  if (action === 'refresh') await f.model.refresh();
  if (action === 'line') f.model.selectLine(0);
  if (action === 'resume') f.model.resume();
  if (action === 'open') { f.plan('replacement'); await f.model.open('huya', 'replacement', null); }
  if (action === 'dispose') f.model.dispose();
  pending.resolve(urls('target')); await work;
  assert.equal(f.model.roomId, action === 'open' ? 'replacement' : 'old', action);
  assert.equal(f.model.switchSeq, 0, action);
  assert.equal(f.events.some(s => s.startsWith('open:target:')), false, action);
  if (action !== 'dispose') f.model.dispose();
}

// Pending relay registration is isolated and immediately disposed on rapid cancellation.
for (const action of ['same-current', 'new-target', 'dispose']) {
  const f = fixture(); await f.openOld('douyu'); const oldRelay = f.relays[0];
  f.plan('target', 'douyu'); const registration = f.deferRelay();
  const first = f.model.switchTo('douyu', 'target', null); await flush();
  const candidate = f.relays[1]; assert.ok(candidate); assert.equal(candidate.disposed, false);
  assert.equal(oldRelay.disposed, false); assert.equal(oldRelay.registrations.length, 1);
  if (action === 'same-current') await f.model.switchTo('douyu', 'old', null);
  if (action === 'new-target') { f.plan('new'); await f.model.switchTo('huya', 'new', null); }
  if (action === 'dispose') f.model.dispose();
  assert.equal(candidate.disposed, true, 'do not wait for stale registration to resolve');
  registration.resolve(['relay:stale']); await first;
  assert.equal(candidate.disposals, 1); assert.equal(f.events.some(s => s.startsWith('open:target:')), false);
  if (action === 'same-current') assert.equal(oldRelay.disposed, false);
  if (action !== 'dispose') f.model.dispose();
}

// Successful Douyu commit transfers candidate ownership once; preserves old relay until ready.
{
  const f = fixture(); await f.openOld('douyu'); const oldRelay = f.relays[0];
  f.plan('target', 'douyu'); const gate = f.deferRelay();
  const work = f.model.switchTo('douyu', 'target', null); await flush();
  const candidate = f.relays[1]; assert.equal(oldRelay.disposed, false);
  gate.resolve(['relay:new']); await work;
  assert.equal(oldRelay.disposed, true); assert.equal(oldRelay.disposals, 1);
  assert.equal(f.model.relay, candidate); assert.equal(candidate.disposed, false);
  assert.deepEqual(Array.from(f.model.lines), ['relay:new']);
  assert.equal(f.timers.size, 1, 'upstream expiry, not opaque relay URLs, schedules renewal');
  f.model.dispose(); assert.equal(candidate.disposals, 1);
}

// A user pause during preparation is honored at commit; no forced unpause on target activation.
{
  const f = fixture(); await f.openOld(); const gate = deferred<PlayUrls>();
  f.plan('target', 'huya', { u: gate.promise });
  const work = f.model.switchTo('huya', 'target', null); await flush(); f.player.pause();
  gate.resolve(urls('target')); await work;
  assert.equal(f.model.roomId, 'target'); assert.equal(f.player.wantsPlayback, false);
  assert.ok(f.events.includes('open:target:false')); f.model.dispose();
}

// Old automatic recovery stays available while preparing; it must not cancel the chosen target.
{
  const f = fixture(); await f.openOld(); const gate = deferred<PlayUrls>();
  f.plan('target', 'huya', { u: gate.promise });
  const work = f.model.switchTo('huya', 'target', null); await flush();
  assert.equal(f.player.onLinesExhausted('old interrupted'), true); await flush();
  assert.ok(f.events.includes('open:old:true')); assert.equal(f.model.roomId, 'old');
  gate.resolve(urls('target')); await work;
  assert.equal(f.model.roomId, 'target'); assert.equal(f.model.switchSeq, 1); f.model.dispose();
}

// A current-room request already in flight cannot reopen old sources after target commit.
{
  const f = fixture(); await f.openOld(); const oldUrls = deferred<PlayUrls>();
  f.plan('old', 'huya', { u: oldUrls.promise });
  const refresh = f.model.refresh(); await flush();
  f.plan('target'); await f.model.switchTo('huya', 'target', null);
  oldUrls.resolve(urls('old')); await refresh;
  assert.equal(f.model.roomId, 'target'); assert.equal(f.model.switchSeq, 1);
  assert.equal(f.events.some(s => s.startsWith('open:old:')), false); f.model.dispose();
}

// A pending old relay registration also cannot overwrite the newly committed relay/source.
{
  const f = fixture(); await f.openOld('douyu'); const oldRelay = f.relays[0];
  const gate = f.deferRelay(); const refresh = f.model.refresh(); await flush();
  f.plan('target', 'douyu'); await f.model.switchTo('douyu', 'target', null);
  const targetRelay = f.model.relay; assert.equal(oldRelay.disposed, true);
  gate.resolve(['relay:old-late']); await refresh;
  assert.equal(f.model.relay, targetRelay); assert.equal(targetRelay.disposed, false);
  assert.equal(f.model.roomId, 'target'); assert.equal(f.events.includes('open:old:true'), false);
  f.model.dispose();
}

// Awaited player activation from a superseded commit cannot reattach retired chat afterward.
{
  const f = fixture(); await f.openOld(); f.plan('first'); const gate = f.deferOpen();
  const first = f.model.switchTo('huya', 'first', null); await flush();
  assert.equal(f.model.roomId, 'first'); f.plan('second');
  await f.model.switchTo('huya', 'second', null); gate.resolve(); await first;
  assert.equal(f.model.roomId, 'second'); assert.equal(f.model.switchSeq, 2);
  assert.deepEqual(f.history, ['first', 'second']); assert.equal(f.chats.length, 3);
  assert.equal(f.chats[1].stopped, true, 'committed first-room chat retires at second commit');
  f.model.dispose();
}

// Old chat remains live during preparation, but callbacks are invalidated at commit.
{
  const f = fixture(); await f.openOld(); let bullets = 0; f.model.onBullet = () => bullets++;
  const oldDm = f.chats[0], gate = deferred<PlayUrls>(); f.plan('target', 'huya', { u: gate.promise });
  const work = f.model.switchTo('huya', 'target', null); await flush();
  oldDm.onMessage(LiveMessage.chat('fixture', 'before commit', 0xffffff));
  assert.equal(bullets, 1); gate.resolve(urls('target')); await work;
  oldDm.onMessage(LiveMessage.chat('fixture', 'stale after commit', 0xffffff));
  assert.equal(bullets, 1); assert.equal(f.model.retainedChats.length, 0);
  f.chats[1].onMessage(LiveMessage.chat('fixture', 'new room', 0xffffff));
  assert.equal(bullets, 2); f.model.dispose();
}
// Cancellation at earlier preparation stages prevents even requesting subsequent stages.
for (const stage of ['detail', 'qualities']) {
  const f = fixture(); await f.openOld(); const gate = deferred<any>();
  f.plan('target', 'huya', stage === 'detail' ? { d: gate.promise } : { q: gate.promise });
  const work = f.model.switchTo('huya', 'target', null); await flush();
  await f.model.switchTo('huya', 'old', null);
  gate.resolve(stage === 'detail' ? detail('target') : qualities()); await work;
  assert.equal(f.model.roomId, 'old'); assert.equal(f.model.switchSeq, 0);
  assert.equal(f.events.some(s => s.startsWith('urls:target:')), false);
  if (stage === 'detail') assert.equal(f.events.includes('qualities:target'), false);
  f.model.dispose();
}

// Scheduled old-room URL renewal, like recovery, does not silently cancel pending user intent.
{
  const f = fixture(); await f.openOld(); const gate = deferred<PlayUrls>();
  f.plan('target', 'huya', { u: gate.promise });
  const work = f.model.switchTo('huya', 'target', null); await flush();
  const renew = [...f.timers.values()][0]; assert.ok(renew); renew(); await flush();
  assert.ok(f.events.includes('open:old:true')); gate.resolve(urls('target')); await work;
  assert.equal(f.model.roomId, 'target'); assert.equal(f.model.switchSeq, 1); f.model.dispose();
}

// A late failure in superseded target activation must not overlay a newer quality operation.
{
  const f = fixture(); await f.openOld(); f.plan('target'); const gate = f.deferOpen();
  const work = f.model.switchTo('huya', 'target', null); await flush();
  assert.equal(f.model.roomId, 'target'); await f.model.selectQuality(0);
  gate.reject(new Error('superseded native open')); await work;
  assert.equal(f.model.error, ''); assert.equal(f.model.qualityIndex, 0); f.model.dispose();
}

// A native activation failure after commit is explicitly an error of the newly committed room.
{
  const f = fixture(); await f.openOld(); f.plan('target'); const gate = f.deferOpen();
  const work = f.model.switchTo('huya', 'target', null); await flush();
  gate.reject(new Error('activation failed')); await work;
  assert.equal(f.model.roomId, 'target'); assert.equal(f.model.switchSeq, 1);
  assert.equal(f.model.error, 'activation failed'); assert.equal(f.model.loading, false); f.model.dispose();
}

// Models are terminal after disposal; no source operations/notices are resurrected.
{
  const f = fixture(); await f.openOld(); f.model.dispose(); f.events.length = 0;
  const notice = f.player.notice; f.plan('target'); await f.model.switchTo('huya', 'target', null);
  await f.model.open('huya', 'target', null); await f.model.refresh();
  await f.model.selectQuality(0); f.model.selectLine(0); f.model.resume();
  assert.deepEqual(f.events, []); assert.equal(f.player.notice, notice);
}
console.log('Room switch: deferred prepare/commit, failures, rapid cancellation, relay ownership, pause, recovery/renewal and stale callbacks passed');
