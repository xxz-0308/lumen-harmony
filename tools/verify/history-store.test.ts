import assert from 'node:assert/strict';
import { LiveRoomDetail } from '../../entry/src/main/ets/core/model/Models';
import { getTestPreference, setTestPreference } from './kit-prefs';

Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {}
});
const { FollowStore, HistoryStore } = await import('../../entry/src/main/ets/app/Stores');
const store = HistoryStore.inst;
store.load({} as never);
let events = 0;
const onChange = (): void => { events++; };
store.subscribe(onChange);
const room = new LiveRoomDetail();
room.siteId = 'douyu';
room.roomId = 'test';
room.title = 'temporary test room';
store.record(room);
assert.equal(store.items.length, 1);
assert.equal(events, 1);
store.clear();
assert.equal(store.items.length, 0);
assert.equal(events, 2);
store.unsubscribe(onChange);
store.record(room);
assert.equal(events, 2, 'unsubscribed views do not receive stale notifications');
store.load({} as never);
assert.equal(store.items.length, 1, 'test Preferences retains final record');
setTestPreference('lumen_history', 'list', '{');
store.load({} as never);
assert.ok(store.storageError.length > 0);
store.clear();
assert.equal(getTestPreference('lumen_history', 'list'), '{', 'corrupt data is never overwritten');
const history = Array.from({ length: 205 }, (_, i) => ({
  siteId: 'douyu', roomId: `room-${i}`, userName: 'fixture', avatar: '',
  title: `room ${i}`, cover: '', area: '', watchedAt: 1000 + i
}));
setTestPreference('lumen_history', 'list', JSON.stringify([
  null,
  { siteId: 'douyu', roomId: '', watchedAt: 9999 },
  { siteId: 'douyu', roomId: 'invalid-date', watchedAt: 'yesterday' },
  ...history,
  { ...history[204], title: 'most recent duplicate', watchedAt: 2000 }
]));
store.load({} as never);
assert.equal(store.storageError, '', 'malformed individual rows do not hide the healthy history');
assert.equal(store.items.length, 200, 'loaded history uses the same 200-room cap as record');
assert.equal(store.items[0].roomId, 'room-204', 'latest visit is first even for unsorted persisted rows');
assert.equal(store.items[0].title, 'most recent duplicate');
assert.equal(new Set(store.items.map((item) => `${item.siteId}:${item.roomId}`)).size, 200);
let recentIds: string[] = [];
const syncRecent = (): void => { recentIds = store.items.slice(0, 4).map((item) => item.roomId); };
store.subscribe(syncRecent);
store.record(room);
assert.equal(store.items.length, 200);
assert.equal(recentIds[0], room.roomId);
store.clear();
assert.deepEqual(recentIds, [], 'all mounted history consumers immediately see the same empty state');
store.unsubscribe(syncRecent);
const follows = [
  { siteId: 'douyu', roomId: 'valid', userName: 'fixture', avatar: '', addTime: 1 },
  { siteId: 'douyu', roomId: 'valid', userName: 'duplicate', avatar: '', addTime: 2 },
  { siteId: 'huya', roomId: '', userName: 'no room', avatar: '', addTime: 3 },
  { siteId: 'unknown', roomId: '123', userName: 'bad site', avatar: '', addTime: 4 }
];
setTestPreference('lumen_follows', 'list', JSON.stringify(follows));
FollowStore.inst.load({} as never);
assert.equal(FollowStore.inst.items.length, 1, 'duplicates, empty room IDs and unknown sites are rejected');
assert.equal(FollowStore.inst.items[0].userName, 'fixture');
console.log('History/Follow stores: clear notifications, corrupt protection and follow dedupe passed');
