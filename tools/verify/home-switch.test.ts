import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { transform } from 'esbuild';
import { LiveRoomItem, SiteId } from '../../entry/src/main/ets/core/model/Models';

Object.assign(globalThis, { ObservedV2: (value: unknown) => value, Trace: () => {} });
const { HomeHeroState } = await import('../../entry/src/main/ets/views/HomeHeroState');
const { RoomFeed } = await import('../../entry/src/main/ets/app/RoomFeed');
const room = (site: SiteId, id: string, title = id) => LiveRoomItem.of(site, id, title, `${site}/${id}/${title}`, id, 1);
const a = room('huya', '1'), b = room('douyu', '1'), c = room('bilibili', '1');
assert.deepEqual(HomeHeroState.fallback([[a, room('huya', '2')], [b, room('douyu', '2')], [c, room('bilibili', '2')]]),
  [a, b, c, room('huya', '2'), room('douyu', '2'), room('bilibili', '2')]);
assert.deepEqual(HomeHeroState.fallback([[a, a], [], [c]]), [a, c], 'fallback deduplicates room keys, not numeric ids across sites');
assert.equal(HomeHeroState.fallback([[], [], []]).length, 0);
assert.equal(HomeHeroState.fallback([Array.from({ length: 20 }, (_, i) => room('huya', String(i)))]).length, 6);

const hero = new HomeHeroState();
hero.update([a, b, c], true); hero.setActive(true);
let epoch = hero.generation;
hero.select(1, epoch); hero.transition(1, 0.5, epoch);
assert.equal(hero.slides[1].opacity, 0.65);
const reused = hero.slides[1];
hero.update([c, room('douyu', '1', 'new snapshot'), a], true);
assert.equal(hero.index, 1); assert.equal(hero.slides[1], reused);
assert.equal(hero.slides[1].item.title, 'new snapshot', 'a reused slide updates visual and navigation input together');
assert.equal(hero.slides[1].opacity, 1); assert.equal(hero.slides[1].shift, 0);
hero.select(2, epoch); hero.transition(1, -1, epoch); hero.finish(2, epoch);
assert.equal(hero.index, 1, 'callbacks from the old ordered source cannot take over');
assert.equal(hero.slides[1].opacity, 1);
hero.update([a, c, b], true); assert.equal(hero.index, 2, 'keep the selected room through reorder');
const unchangedEpoch = hero.generation, unchangedSlides = hero.slides;
hero.update([room('huya', '1', 'updated'), c, b], true);
assert.equal(hero.slides, unchangedSlides, 'same ordered identities keep the carousel container');
assert.equal(hero.index, 2); assert.equal(hero.generation, unchangedEpoch, 'a same-identity update is not a new carousel');
hero.beginTouch(); hero.update([c], false);
assert.equal(hero.slides.length, 3); assert.equal(hero.fromFollows, true, 'touch freezes the room under the finger');
hero.endTouch(); assert.equal(hero.index, 0); assert.equal(hero.slides[0].item, c); assert.equal(hero.fromFollows, false);
epoch = hero.generation; hero.transition(0, 0.8, epoch); hero.finish(0, epoch);
assert.equal(hero.slides[0].opacity, 1); assert.equal(hero.slides[0].shift, 0);
hero.transition(0, 1, epoch); assert.equal(hero.slides[0].opacity, 1, 'a late proxy cannot dim a settled slide');
hero.update([], false); assert.equal(hero.index, 0); assert.equal(hero.slides.length, 0);
hero.select(20, hero.generation); assert.equal(hero.index, 0);
hero.update([a, b], true); epoch = hero.generation; hero.setActive(false);
hero.select(1, epoch); hero.transition(0, 1, hero.generation); assert.equal(hero.index, 0); assert.equal(hero.slides[0].opacity, 1);

// Compile production non-UI methods, as in component-task-lifecycle.test.ts. Layout, native
// nested scrolling and actual presented animation are checked on the tablet, not simulated here.
async function logicStruct(file: string, name: string, end: string, mocks: Record<string, unknown>) {
  const src = readFileSync(new URL(file, import.meta.url), 'utf-8');
  const marker = `export struct ${name} {`, start = src.indexOf(marker) + marker.length;
  assert.ok(start >= marker.length);
  const body = src.slice(start, src.indexOf(end, start))
    .replace(/^\s*@(Param|Local|Event|BuilderParam)\s+/gm, '\n  ')
    .replace(/^\s*@(Monitor\([^\n]*\)|Computed)\s*\n/gm, '\n');
  const key = `__home_fixture_${name}`;
  (globalThis as any)[key] = mocks;
  const output = await transform(`const {${Object.keys(mocks).join(',')}}=globalThis.${key};\nexport class ${name} {${body}\n}`,
    { loader: 'ts', target: 'es2022', format: 'esm' });
  return (await import(`data:text/javascript,${encodeURIComponent(output.code)}`))[name];
}
let nextTimer = 0;
const timers = new Map<number, () => void>();
const ids: SiteId[] = ['huya', 'douyu', 'bilibili'];
const cache = new Map<SiteId, InstanceType<typeof RoomFeed>>();
const loads = new Map<SiteId, number>();
for (const id of ids) {
  cache.set(id, new RoomFeed(async () => { loads.set(id, (loads.get(id) ?? 0) + 1); return { items: [], hasMore: false }; }));
  cache.get(id)!.items = [room(id, '1')];
}
class Scroller {
  y = 0; limit = 1000;
  currentOffset() { return { xOffset: 0, yOffset: this.y }; }
  scrollTo(options: { yOffset: number; animation: boolean }) { this.y = Math.min(this.limit, options.yOffset); }
}
const settings = { homeSite: 'huya', scheduleSave() {} };
const env = { winHeight: 700, foreground: true, reduceMotion: false };
const followStore = { items: [] as any[], contentRevision: 0, subscribe() {}, unsubscribe() {}, refreshAll() {} };
const Home = await logicStruct('../../../entry/src/main/ets/views/HomeView.ets', 'HomeView', '  @Builder\n  liveStrip()', {
  Settings: { inst: settings }, AppEnv: { inst: env }, Sites: { ids }, Scroller, HomeHeroState, Motion: { snappy: 0 },
  Feeds: { recommendOf: (id: SiteId) => cache.get(id) },
  CategoryStore: { favorites: () => [], subscribeFavorites() {}, unsubscribeFavorites() {} },
  FollowStore: { inst: followStore },
  setTimeout: (fn: () => void) => { const id = ++nextTimer; timers.set(id, fn); return id; },
  clearTimeout: (id: number) => timers.delete(id)
});
const finishes: (() => void)[] = [];
const home = new Home(); home.active = true;
home.getUIContext = () => ({ animateTo: (options: { onFinish: () => void }, change: () => void) => {
  finishes.push(options.onFinish); change();
} });
home.aboutToAppear();
assert.equal(home.siteOffset('huya'), 0); assert.equal(home.siteOffset('douyu'), 28); assert.equal(home.siteOffset('bilibili'), 28);
const commonKeys = home.heroItems.map(HomeHeroState.key);
home.outerScroller.y = 140; home.onListScroll('huya', 321);
home.selectSite(1);
assert.equal(home.alignY, 321); assert.equal(home.outerScroller.y, 140);
assert.deepEqual(home.heroItems.map(HomeHeroState.key), commonKeys, 'platform choice does not change the common fallback');
home.onListScroll('huya', 900); assert.equal(home.listY, 321, 'outgoing lists cannot replace the shared offset');
home.onListScroll('douyu', 275); home.selectSite(2);
assert.equal(home.alignY, 275); home.selectSite(0);
assert.equal(home.alignY, 275); assert.equal(home.site, 'huya'); assert.equal(timers.size, 0);
assert.deepEqual(home.drawnSites, ids);
finishes[0](); finishes[1]();
assert.deepEqual(home.drawnSites, ids, 'old animation completions cannot hide the newest outgoing/incoming layers');
finishes[2](); assert.deepEqual(home.drawnSites, ['huya']);
assert.equal(home.outerScroller.y, 140); assert.equal(home.listY, 275, 'completion does not restore an old offset');
home.selectSite(0); home.selectSite(99); assert.equal(finishes.length, 3);
assert.equal(loads.size, 0, 'switches use populated RoomFeed caches without first-page requests');
home.selectSite(2); assert.equal(home.siteOffset('huya'), -28); assert.equal(home.siteOffset('douyu'), -28);
const interrupted = finishes.at(-1)!;
env.reduceMotion = true; home.selectSite(0);
assert.equal(home.siteOffset('douyu'), 0); assert.deepEqual(home.drawnSites, ['huya']);
interrupted(); assert.deepEqual(home.drawnSites, ['huya'], 'reduced motion invalidates an older animated cleanup');
assert.equal(settings.homeSite, 'huya'); env.reduceMotion = false;
home.selectSite(1); const detachedFinish = finishes.at(-1)!;
home.aboutToDisappear(); const detachedSites = home.drawnSites; detachedFinish();
assert.equal(home.drawnSites, detachedSites); assert.equal(timers.size, 0);
home.selectSite(0); assert.equal(home.site, 'douyu');

const retainedHome = new Home(); retainedHome.active = true; retainedHome.aboutToAppear();
const snapshot = retainedHome.followSnapshot;
retainedHome.syncFollows(); assert.equal(retainedHome.followSnapshot, snapshot, 'status-only follow notifications keep the Home snapshot');
retainedHome.heroVisible = false; assert.equal(retainedHome.heroActive, false);
retainedHome.heroVisible = true; assert.equal(retainedHome.heroActive, true);
retainedHome.active = false; retainedHome.onActive();
followStore.items = [{ isLive: true, online: 1, toRoomItem: () => a }]; followStore.contentRevision++;
retainedHome.syncFollows(); assert.equal(retainedHome.followSnapshot, snapshot, 'hidden Home defers snapshot publication');
retainedHome.active = true; retainedHome.onActive(); assert.equal(retainedHome.followSnapshot.length, 1);
assert.equal(retainedHome.heroItems[0], a); retainedHome.aboutToDisappear();

const covers: string[] = [];
const HeroView = await logicStruct('../../../entry/src/main/ets/views/HomeHero.ets', 'HomeHero', '  @Builder\n  placeholder()', {
  HomeHeroState, TouchType: { Down: 1, Up: 2, Cancel: 3 },
  setTimeout: (fn: () => void) => { const id = ++nextTimer; timers.set(id, fn); return id; },
  clearTimeout: (id: number) => timers.delete(id)
});
const heroView = new HeroView(); heroView.active = true; heroView.items = [a, b];
heroView.onCover = (cover: string) => covers.push(cover); heroView.aboutToAppear();
const nativeChange = heroView.changeHandler(heroView.state.generation);
heroView.touch({ type: 1 }); heroView.items = [c]; heroView.onSource();
assert.equal(heroView.state.slides[0].item, a);
heroView.touch({ type: 2 }); assert.equal(timers.size, 1);
heroView.aboutToDisappear(); const coverCount = covers.length;
assert.equal(timers.size, 0); nativeChange(1); heroView.touch({ type: 2 });
assert.equal(covers.length, coverCount, 'detached carousel callbacks cannot update the common ambient image');
assert.equal(timers.size, 0, 'detached touch callbacks cannot create release timers');

const Grid = await logicStruct('../../../entry/src/main/ets/components/RoomGrid.ets', 'RoomGrid', '  @Builder\n  noHeader()', {
  RoomFeed, ListScroller: Scroller, Layout: { pageBottom: 30 }, Space: { page: 24 }
});
const grid = new Grid(); let aligned = -1; grid.onScrollY = (y: number) => { aligned = y; };
grid.scroller.limit = 128; grid.alignSeq = 1; grid.alignY = 400; grid.onAlign();
assert.equal(aligned, 128, 'publish actual native clamping instead of an invented target offset');
assert.equal(grid.nested, false); assert.equal(grid.externalRefresh, false, 'other screens keep their existing scrolling/refresh defaults');
const homeSrc = readFileSync(new URL('../../../entry/src/main/ets/views/HomeView.ets', import.meta.url), 'utf-8');
assert.equal((homeSrc.match(/HomeHero\(\{/g) ?? []).length, 1);
assert.equal(homeSrc.includes('Swiper()'), false);
const heroSrc = readFileSync(new URL('../../../entry/src/main/ets/views/HomeHero.ets', import.meta.url), 'utf-8');
assert.equal(heroSrc.includes('.clip(false)'), false, 'adjacent hero slides cannot draw into the common page gutter');
console.log('Home: common hero identity, stale proxy rejection, cached site switching and shared offset passed');
