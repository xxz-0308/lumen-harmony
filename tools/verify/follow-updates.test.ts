import assert from 'node:assert/strict';
import { LiveRoomDetail } from '../../entry/src/main/ets/core/model/Models';
import { setTestPreference } from './kit-prefs';

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
console.log('FollowStore: content/status revisions, stable items, progressive refresh, throttle and forced follow-up passed');
