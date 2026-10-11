import assert from 'node:assert/strict';
import { LiveRoomDetail } from '../../entry/src/main/ets/core/model/Models';
import { getTestPreference, getTestPreferenceStats, resetTestPreferenceStats, setTestFlushHook, setTestPreference } from './kit-prefs';

Object.assign(globalThis, { ObservedV2: (value: unknown) => value, Trace: () => {} });
const { FollowStore } = await import('../../entry/src/main/ets/app/Stores');
const { Sites } = await import('../../entry/src/main/ets/core/sites/Sites');
const flush = async () => { for (let i = 0; i < 16; i++) await Promise.resolve(); };
function detail(id: string, online = 10) {
  const d = new LiveRoomDetail(); d.siteId = 'huya'; d.roomId = id; d.userName = 'fixture';
  d.status = true; d.title = 'fixture title'; d.cover = 'fixture cover'; d.online = online; return d;
}
setTestPreference('lumen_follows', 'list', '[]');
const store = new FollowStore(); store.load({} as never);
let calls = 0, events = 0;
Sites.huya.getRoomDetail = async id => { calls++; return detail(id); };
store.subscribe(() => { events++; });
store.follow(detail('one')); const item = store.items[0], revision = store.contentRevision;
await flush(); assert.equal(store.contentRevision, revision, 'save completion is status-only');
store.updateFromDetail(detail('one')); assert.equal(store.contentRevision, revision);
await store.refreshAll(true); assert.equal(store.contentRevision, revision, 'an unchanged refresh does not invalidate list snapshots');
assert.equal(store.items[0], item); assert.equal(store.refreshing, false); assert.ok(store.lastRefreshAt > 0); assert.ok(events >= 4);
const afterRefresh = calls; await store.refreshAll(); assert.equal(calls, afterRefresh, 'automatic throttle is preserved');
store.updateFromDetail(detail('one', 20)); assert.equal(store.contentRevision, revision + 1); assert.equal(store.items[0], item);
const changedRevision = store.contentRevision; store.unfollow('huya', 'missing'); assert.equal(store.contentRevision, changedRevision);

setTestPreference('lumen_follows', 'list', JSON.stringify(Array.from({ length: 6 }, (_, i) => ({
  siteId: 'huya', roomId: String(i), userName: 'fixture', avatar: '', addTime: i
}))));
const progressive = new FollowStore(); progressive.load({} as never);
const firstRevision = progressive.contentRevision;
let active = 0, peak = 0, requests = 0;
const waiters: { id: string; resolve: (d: LiveRoomDetail) => void }[] = [];
Sites.huya.getRoomDetail = async id => {
  active++; requests++; peak = Math.max(active, peak);
  const d = await new Promise<LiveRoomDetail>(resolve => waiters.push({ id, resolve })); active--; return d;
};
const sweep = progressive.refreshAll(true); await progressive.refreshAll(true);
assert.equal(peak, 4, 'refresh concurrency stays at four');
while (waiters.length || active || progressive.refreshing) {
  for (const waiter of waiters.splice(0)) waiter.resolve(detail(waiter.id));
  await flush();
}
await sweep; assert.equal(requests, 12, 'a forced request during refresh queues one follow-up');
assert.equal(progressive.contentRevision, firstRevision + 6, 'only the changed first sweep invalidates content');
assert.equal(progressive.items.length, 6); assert.ok(progressive.items.every(f => f.isLive));

let resolve!: (d: LiveRoomDetail) => void;
Sites.huya.getRoomDetail = () => new Promise(yes => { resolve = yes; });
progressive.followAnchor('huya', 'retired', 'fixture', '', true);
const retired = progressive.items[0]; progressive.unfollow('huya', 'retired');
const afterRemoval = progressive.contentRevision; resolve(detail('retired', 999)); await flush();
assert.equal(progressive.contentRevision, afterRemoval, 'a late unfollowed result does not invalidate current content');
assert.equal(retired.online, 0);
const name='lumen_follows';
setTestPreference(name,'list',JSON.stringify([{siteId:'huya',roomId:'saved',userName:'fixture',avatar:'',addTime:1,tag:''}]));
const saved=new FollowStore();saved.load({} as never);resetTestPreferenceStats(name);
Sites.huya.getRoomDetail=async id=>detail(id,123);
await saved.refreshAll(true);await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:0,flush:0},'transient refresh does not serialize/write unchanged saved fields');
saved.items[0].tag='fixture tag';saved.items[0].addTime=2;
await saved.refreshAll(true);await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:1,flush:1});
assert.equal(JSON.parse(getTestPreference(name,'list')!)[0].tag,'fixture tag');
const renamed=detail('saved');renamed.userName='renamed fixture';renamed.userAvatar='fixture-avatar';
saved.updateFromDetail(renamed);await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:2,flush:2});
Sites.huya.getRoomDetail=async()=>renamed;await saved.refreshAll(true);await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:2,flush:2});
saved.unfollow('huya','saved');await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:3,flush:3});

setTestPreference(name,'list','[]');const failed=new FollowStore();failed.load({} as never);resetTestPreferenceStats(name);
setTestFlushHook(name,async()=>{throw new Error('fixture flush failure');});
failed.follow(detail('retry'));await flush();assert.ok(failed.saveError.length>0);
setTestFlushHook(name,null);Sites.huya.getRoomDetail=async id=>detail(id);
await failed.refreshAll(true);await flush();assert.equal(failed.saveError,'');assert.deepEqual(getTestPreferenceStats(name),{putSync:2,flush:2},'failed snapshots remain retryable');
await failed.refreshAll(true);await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:2,flush:2});

setTestPreference(name,'list','[]');const queued=new FollowStore();queued.load({} as never);resetTestPreferenceStats(name);
let inFlight=0,flushPeak=0;const completions:(()=>void)[]=[];
setTestFlushHook(name,()=>new Promise<void>(resolve=>{inFlight++;flushPeak=Math.max(flushPeak,inFlight);completions.push(()=>{inFlight--;resolve();});}));
queued.follow(detail('old'));await flush();queued.follow(detail('new'));queued.unfollow('huya','old');queued.items[0].tag='latest edit';
assert.deepEqual(getTestPreferenceStats(name),{putSync:1,flush:1},'edits do not mutate preference data during an older flush');
completions.shift()!();await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:2,flush:2});
assert.equal(flushPeak,1,'flush ownership is serial');
assert.deepEqual(JSON.parse(getTestPreference(name,'list')!).map((f:any)=>[f.roomId,f.tag]),[['new','latest edit']]);
completions.shift()!();await flush();setTestFlushHook(name,null);
await queued.refreshAll(true);await flush();assert.deepEqual(getTestPreferenceStats(name),{putSync:2,flush:2},'the newer successful snapshot is not dirtied by older completion');

setTestPreference(name,'list','[]');const anchor=new FollowStore();anchor.load({} as never);resetTestPreferenceStats(name);
anchor.followAnchor('huya','anchor','placeholder','',false);await flush();
assert.equal(JSON.parse(getTestPreference(name,'list')!)[0].userName,'fixture','standalone detail changes are included in the subsequent saved snapshot');
console.log('FollowStore: revisions, progressive refresh, throttle, unchanged/transient zero-write, persisted fields, failure retry, serial in-flight edits and standalone details passed');
