import assert from 'node:assert/strict';
import { RoomPage } from '../../entry/src/main/ets/core/model/Models';

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
console.log('SearchModel: per-site retry, duplicate suppression, history and feed reuse passed');
