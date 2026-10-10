import assert from 'node:assert/strict';
import { LiveRoomItem, RoomPage } from '../../entry/src/main/ets/core/model/Models';

Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {}
});
const { RoomFeed } = await import('../../entry/src/main/ets/app/RoomFeed');

const room = (id: string): LiveRoomItem => LiveRoomItem.of('douyu', id, id, '', '', 0);
const page = (id: string, more: boolean = true): RoomPage => new RoomPage([room(id)], more);

const calls: number[] = [];
let failFirstRefresh = false;
let failSecondPage = false;
const feed = new RoomFeed(async (n: number): Promise<RoomPage> => {
  calls.push(n);
  if (n === 1 && failFirstRefresh) {
    failFirstRefresh = false;
    throw new Error('refresh failed');
  }
  if (n === 2 && failSecondPage) {
    failSecondPage = false;
    throw new Error('page failed');
  }
  return page(String(n) + '-' + calls.length);
});

await feed.load();
assert.equal(feed.items.length, 1);
failFirstRefresh = true;
await feed.load(true);
assert.equal(feed.pageError.length > 0, true);
assert.equal(feed.items.length, 1);
const retained = feed.items;
await feed.loadMore();
assert.deepEqual(calls, [1, 1], 'reach-end cannot bypass the failed first-page refresh');
assert.equal(feed.items, retained);
feed.retryMore();
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.deepEqual(calls, [1, 1, 1], 'failed pull refresh retries page one');
assert.equal(feed.pageError, '');

failSecondPage = true;
await feed.loadMore();
assert.equal(feed.pageError.length > 0, true);
assert.equal(feed.hasMore, false);
feed.retryMore();
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.deepEqual(calls, [1, 1, 1, 2, 2], 'failed pagination retries page two');
assert.equal(feed.items.length, 2);
assert.equal(feed.pageError, '');
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(yes => { resolve = yes; });
  return { promise, resolve };
}
const append = deferred<RoomPage>(), replacement = deferred<RoomPage>();
let first = true;
const overlap = new RoomFeed(n => n === 1 ? (first ? (first = false, Promise.resolve(page('initial'))) : replacement.promise) : append.promise);
await overlap.load(); const more = overlap.loadMore(); const refresh = overlap.load(true);
append.resolve(page('stale-append')); await more;
assert.equal(overlap.refreshing, true); assert.equal(overlap.items[0].roomId, 'initial');
replacement.resolve(page('replacement')); await refresh;
assert.deepEqual(overlap.items.map(item => item.roomId), ['replacement']);
console.log('RoomFeed: retained refresh retry, append retry and stale pagination rejection passed');
