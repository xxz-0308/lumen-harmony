import assert from 'node:assert/strict';
import { LiveRoomItem } from '../../entry/src/main/ets/core/model/Models';

class FakeNavPathStack {
  paths: { name: string; param: unknown }[] = [];
  operations: string[] = [];
  getAllPathName(): string[] { return this.paths.map(p => p.name); }
  pushPath(p: { name: string; param: unknown }): void {
    this.operations.push('push');
    this.paths.push(p);
  }
  replacePath(p: { name: string; param: unknown }): void {
    this.operations.push('replace');
    this.paths[this.paths.length - 1] = p;
  }
  pop(): void { this.paths.pop(); }
}
Object.assign(globalThis, { NavPathStack: FakeNavPathStack, LaunchMode: { NEW_INSTANCE: 1 },
  ObservedV2: (value: unknown) => value, Trace: () => {} });
const { Nav, LiveRouteParam } = await import('../../entry/src/main/ets/app/Nav');
const { NavigationActivity } = await import('../../entry/src/main/ets/app/NavigationActivity');
const activity = NavigationActivity.inst;
const stack = Nav.stack as unknown as FakeNavPathStack;
const item = new LiveRoomItem();
item.siteId = 'huya';
item.roomId = '691406';
item.cover = 'https://example.test/cover.jpg';
Nav.openLive(item, [20, 30, 300, 169]);
assert.equal(activity.rootActive, false, 'root freezes before destination readiness can write follow details');
activity.setRootVisible(true, true);
assert.equal(activity.rootActive, false, 'a transparent destination reporting the nav bar visible cannot wake root content');
let route = stack.paths.at(-1)!.param as InstanceType<typeof LiveRouteParam>;
assert.equal(route.preview, item);
assert.equal(route.siteId, item.siteId);
assert.equal(route.roomId, item.roomId);
assert.deepEqual([route.coverX, route.coverY, route.coverW, route.coverH], [20, 30, 300, 169]);
assert.equal('heroId' in route, false, 'image morph routes do not carry a legacy geometry id');
Nav.openRoom('douyu', '138243');
assert.deepEqual(stack.operations, ['push', 'replace'], 'switching from inside a room does not stack another room');
route = stack.paths.at(-1)!.param as InstanceType<typeof LiveRouteParam>;
assert.equal(route.coverW, -1, 'a direct room has no old card bounds');
assert.equal(route.preview, null);
Nav.back();
assert.equal(stack.paths.length, 0);
for (const rect of [[], [20, 30, 300], [20, 30, 0, 169], [20, 30, 300, 0]]) {
  Nav.openLive(item, rect);
  route = stack.paths.at(-1)!.param as InstanceType<typeof LiveRouteParam>;
  assert.equal(route.coverW, -1, 'invalid card bounds retain the fade-only fallback');
  Nav.back();
}
activity.holdRoot();
activity.setRootVisible(true);
assert.equal(activity.rootActive, false, 'root visibility during pop must not resume list rebuilding during animation');
activity.holdRoot();
activity.releaseRoot();
assert.equal(activity.rootActive, false, 'another retiring destination still holds presentation');
activity.releaseRoot();
assert.equal(activity.rootActive, true);
activity.setRootVisible(false);
activity.holdRoot();
activity.releaseRoot();
assert.equal(activity.rootActive, false, 'popping into a secondary page must not wake the root');
activity.setRootVisible(true);
console.log('Navigation routes: card bounds, preview, direct-entry fallback, replacement and retained-root freeze preserved');
