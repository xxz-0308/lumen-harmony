import assert from 'node:assert/strict';
import { AnchorPage, LiveAnchorItem, LiveRoomItem, RoomPage, SiteId } from '../../entry/src/main/ets/core/model/Models';

Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {}
});
const { Sites } = await import('../../entry/src/main/ets/core/sites/Sites');
const { SearchModel } = await import('../../entry/src/main/ets/app/SearchModel');
const { Settings } = await import('../../entry/src/main/ets/app/Settings');
Settings.inst.load({} as never);
const m = SearchModel.inst;
const requests = new Map<string, number>();
for (const site of Sites.all) {
  site.searchRooms = async (_keyword: string, page: number): Promise<RoomPage> => {
    const key = `${site.id}_${page}`;
    requests.set(key, (requests.get(key) ?? 0) + 1);
    if (site.id === 'huya' && requests.get(key) === 1) {
      throw new Error('simulated network failure');
    }
    return new RoomPage([], false);
  };
}
let updates = 0;
m.onUpdate = () => { updates++; };
m.search('sample');
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(m.results.find((r) => r.siteId === 'huya')?.error, '搜索失败');
const failed = m.results.find((r) => r.siteId === 'huya')!;
m.retry(failed);
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(failed.error, '');
assert.ok(updates >= 2);
const count = [...requests.values()].reduce((a, b) => a + b, 0);
m.search('sample');
assert.equal([...requests.values()].reduce((a, b) => a + b, 0), count,
  'repeat within 15s does not fire three searches again');
assert.equal(Settings.inst.searchHistory[0], 'sample');
m.setFilter('douyu');
const douyu = m.feed;
await new Promise<void>((resolve) => setTimeout(resolve, 0));
m.setFilter('huya');
m.setFilter('douyu');
assert.equal(m.feed, douyu, 'switching search filters preserves the platform feed');
m.clear();
assert.equal(m.searched, false);
function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (error: Error) => void;
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
const pending: { site: SiteId; kw: string; page: number; task: ReturnType<typeof deferred<RoomPage>> }[] = [];
for (const site of Sites.all) {
  site.searchRooms = (kw: string, page: number) => {
    const task = deferred<RoomPage>(); pending.push({ site: site.id, kw, page, task }); return task.promise;
  };
  site.searchAnchors = async (kw: string) => {
    const anchor = new LiveAnchorItem(); anchor.siteId = site.id; anchor.roomId = kw; anchor.liveStatus = true;
    return new AnchorPage([anchor], false);
  };
}
const resultPage = (site: SiteId, id: string) => new RoomPage([LiveRoomItem.of(site, id, id, '', id, 1)], true);
const next = new SearchModel();
next.search(' retained '); const batch = next.results;
next.search('retained'); next.search('retained', true);
assert.equal(pending.length, 3, 'identical in-flight submissions coalesce even when forced');
for (const request of pending.splice(0)) request.task.resolve(resultPage(request.site, 'old'));
await flush(); const oldRooms = next.results[0].rooms;
next.setFilter('huya'); const retainedFeed = next.feed!;
pending.splice(0).forEach(request => request.task.resolve(resultPage(request.site, 'old-feed')));
await flush(); next.search('retained', true);
assert.equal(next.results, batch); assert.equal(next.feed, retainedFeed);
assert.equal(next.results[0].rooms, oldRooms); assert.equal(retainedFeed.items[0].roomId, 'old-feed');
assert.equal(pending.length, 4, 'only the displayed cached feed is refreshed with the three summaries');
for (const request of pending.splice(0)) request.task.reject(new Error('failed refresh'));
await flush(); assert.equal(next.results[0].rooms, oldRooms);
assert.equal(next.results[0].error, '搜索失败'); assert.equal(retainedFeed.items[0].roomId, 'old-feed');
const huya = next.results[0]; next.retry(huya); next.retry(huya);
assert.equal(pending.length, 1, 'busy result retries are deduplicated');
pending.shift()!.task.resolve(resultPage('huya', 'new')); await flush();
assert.equal(huya.rooms[0].roomId, 'new'); assert.equal(huya.error, '');
next.search('different'); const different = next.results;
assert.notEqual(different, batch); assert.equal(different[0].rooms.length, 0);
assert.notEqual(next.feed, retainedFeed);
const obsoleteCount = pending.length; next.retry(huya);
assert.equal(pending.length, obsoleteCount, 'obsolete SiteResult cannot retry the new query');
next.setMode('anchor'); await flush();
assert.equal(next.feed, null); assert.equal(next.results[0].rooms.length, 0);
assert.equal(next.results[0].anchors[0].roomId, 'different');
for (const request of pending.splice(0)) request.task.resolve(resultPage(request.site, 'stale-room'));
await flush(); assert.equal(next.results[0].rooms.length, 0, 'room responses cannot overwrite newer anchor results');
next.setMode('room'); const cleared = next.results; next.clear();
for (const request of pending.splice(0)) request.task.resolve(resultPage(request.site, 'after-clear'));
await flush(); assert.equal(next.results.length, 0); assert.equal(next.searched, false);
assert.equal(cleared[0].rooms.length, 0, 'cleared responses stay rejected');

const lazy = new SearchModel(); lazy.search('lazy');
for (const request of pending.splice(0)) request.task.resolve(resultPage(request.site, 'initial'));
await flush(); lazy.setFilter('huya'); const aFeed = lazy.feed;
pending.splice(0).forEach(request => request.task.resolve(resultPage(request.site, 'initial-feed')));
await flush(); lazy.setFilter('douyu'); const bFeed = lazy.feed;
pending.splice(0).forEach(request => request.task.resolve(resultPage(request.site, 'initial-feed')));
await flush(); lazy.search('lazy', true);
assert.equal(pending.length, 4); assert.equal(lazy.feed, bFeed);
for (const request of pending.splice(0)) request.task.resolve(resultPage(request.site, 'refreshed'));
await flush(); lazy.setFilter('huya'); assert.equal(lazy.feed, aFeed);
assert.equal(pending.length, 1, 'an inactive cached filter refreshes once when next displayed');
pending.shift()!.task.resolve(resultPage('huya', 'refreshed-feed')); await flush();
assert.equal(aFeed!.items[0].roomId, 'refreshed-feed'); lazy.setFilter('douyu'); lazy.setFilter('huya');
assert.equal(pending.length, 0);
console.log('SearchModel: retry/reuse, in-flight dedup, same-query retention, identity isolation and lazy feed refresh passed');
