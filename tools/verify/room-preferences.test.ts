import assert from 'node:assert/strict';
import { getTestPreference, setTestOpenUnavailable, setTestPreference } from './kit-prefs';
import { isNarrowTheater, showTheaterPanel } from '../../entry/src/main/ets/room/TheaterLayout';
import { HeroSource, HeroSources } from '../../entry/src/main/ets/room/HeroSources';

Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {}
});
const { Settings } = await import('../../entry/src/main/ets/app/Settings');
const s = Settings.inst;
const seed = (value: object): void => setTestPreference('lumen_settings', 'data', JSON.stringify(value));
const disk = (): Record<string, unknown> => JSON.parse(getTestPreference('lumen_settings', 'data')!);
seed({ startPage: 'history', sideChat: true });
s.load({} as never);
assert.equal(s.startPage, 'history', 'legacy history intent is retained for navigation migration');
assert.equal(s.theaterPanelOpen, true, 'old snapshots default to an expanded theater panel');
assert.equal(s.sideChat, true);
s.theaterPanelOpen = false;
s.startPage = 'mine';
await s.flush();
s.theaterPanelOpen = true;
s.startPage = 'home';
s.load({} as never);
assert.equal(s.theaterPanelOpen, false, 'explicit close survives a reload');
assert.equal(s.startPage, 'mine', 'new start page round trips');
assert.equal(s.sideChat, true, 'theater preference does not overwrite fullscreen side chat');
seed({ theaterPanelOpen: 'false', sideChat: false, startPage: 'invalid' });
s.load({} as never);
assert.equal(s.theaterPanelOpen, true, 'invalid Boolean falls back without truthy coercion');
assert.equal(s.sideChat, false);
assert.equal(s.startPage, 'home');

// Opening storage fails before the saved settings can be read. Only explicit edits win on retry.
seed({ theaterPanelOpen: false, sideChat: true, startPage: 'history', accentPalette: 'mint' });
setTestOpenUnavailable(true);
s.load({} as never);
s.startPage = 'mine';
s.scheduleSave();
assert.ok(s.storageError.length > 0);
await assert.rejects(s.flush());
setTestOpenUnavailable(false);
s.retryStorage();
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(s.theaterPanelOpen, false, 'untouched disk preference wins over unavailable defaults');
assert.equal(s.sideChat, true);
assert.equal(s.startPage, 'mine', 'edited start page survives storage recovery');
assert.equal(disk().theaterPanelOpen, false);
assert.equal(disk().startPage, 'mine');
assert.equal(s.accentPalette, 'mint');
setTestOpenUnavailable(true);
s.load({} as never);
s.theaterPanelOpen = true;
s.scheduleSave();
setTestOpenUnavailable(false);
s.retryStorage();
await new Promise<void>((resolve) => setTimeout(resolve, 0));
assert.equal(s.theaterPanelOpen, true, 'explicit theater edit is merged after unavailable storage');
assert.equal(disk().theaterPanelOpen, true);
assert.equal(disk().sideChat, true);
s.theaterPanelOpen = false;
s.flushOnExit();
assert.equal(disk().theaterPanelOpen, false, 'exit snapshot also contains the theater preference');

for (const width of [320, 759, 760, 899, 900, 1200]) {
  assert.equal(isNarrowTheater(width), width < 900);
  assert.equal(showTheaterPanel(width, true, true, true), false, 'fullscreen is independent');
  assert.equal(showTheaterPanel(width, false, false, true), false, 'closed preference remains closed');
  assert.equal(showTheaterPanel(width, false, true, false), width >= 900,
    'narrow windows temporarily hide the panel without changing preference');
  assert.equal(showTheaterPanel(width, false, true, true), true, 'narrow drawer remains reachable');
}
assert.equal(s.theaterPanelOpen, false, 'window derivation performs no preference writes');

const source = new HeroSource();
source.mount('hero_home_huya_1');
source.setBounds('20,30,300,169');
source.setVisible(true);
source.capture();
assert.equal(HeroSources.canReturn(source.id), true);
source.setVisible(false);
assert.equal(HeroSources.canReturn(source.id), true, 'navigation occlusion is not source removal');
source.setBounds('20,-200,300,169');
assert.equal(HeroSources.canReturn(source.id), false, 'scrolling/layout change invalidates capture');
source.setVisible(false);
source.capture();
assert.equal(HeroSources.canReturn(source.id), false, 'offscreen source cannot be captured');
source.setVisible(true);
source.capture();
assert.equal(HeroSources.canReturn('hero_mine_huya_1'), false, 'scope must match');
const duplicate = new HeroSource();
duplicate.mount(source.id);
assert.equal(HeroSources.canReturn(source.id), false, 'ambiguous duplicate ids use fade');
duplicate.unmount();
assert.equal(HeroSources.canReturn(source.id), true);
source.mount('hero_home_huya_2');
assert.equal(HeroSources.canReturn('hero_home_huya_1'), false, 'identity replacement invalidates old source');
assert.equal(HeroSources.canReturn(source.id), false, 'replacement is not automatically captured');
source.setBounds('20,30,300,169');
source.setVisible(true);
source.capture();
HeroSources.release(source.id);
assert.equal(HeroSources.canReturn(source.id), false, 'finished navigation releases capture');
source.capture();
source.unmount();
assert.equal(HeroSources.canReturn('hero_home_huya_2'), false, 'removed source cannot be rebound');
assert.equal(HeroSources.canReturn(''), false);
console.log('Room preferences: migration, reload, storage recovery, window derivation and hero source validity');
