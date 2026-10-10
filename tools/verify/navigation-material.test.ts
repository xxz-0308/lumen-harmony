import assert from 'node:assert/strict';
import { deviceInfo } from './kit-device';
import { LiveRoomItem } from '../../entry/src/main/ets/core/model/Models';

class FakeStack {
  paths: { name: string; param?: any }[] = [];
  options: any;
  getAllPathName(): string[] { return this.paths.map((path) => path.name); }
  pushPath(path: { name: string }, options?: any): void { this.paths.push(path); this.options = options; }
  replacePath(path: { name: string }, options?: any): void { this.paths.pop(); this.pushPath(path, options); }
  pop(): void { this.paths.pop(); }
}
Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {},
  $r: (value: string): string => value,
  NavPathStack: FakeStack,
  LaunchMode: { NEW_INSTANCE: 1 },
  Color: { White: '#FFFFFF', Transparent: '#00000000' },
  AdaptiveColor: { AVERAGE: 1 },
  BlurStyleActivePolicy: { FOLLOWS_WINDOW_ACTIVE_STATE: 0 }
});
const { AppEnv } = await import('../../entry/src/main/ets/app/AppEnv');
const { Nav, Routes } = await import('../../entry/src/main/ets/app/Nav');
const stack = Nav.stack as unknown as FakeStack;
Nav.openSearch(); Nav.openSearch();
assert.deepEqual(stack.getAllPathName(), [Routes.search], 'rapid repeated search taps do not duplicate the destination');
Nav.openRoom('huya', 'one');
assert.deepEqual(stack.getAllPathName(), [Routes.search, Routes.live]);
assert.equal(stack.options.launchMode, 1);
Nav.openRoom('douyu', 'two');
assert.equal(stack.paths.length, 2, 'switching live rooms replaces rather than growing the back stack');
assert.equal(stack.paths[1].param.roomId, 'two');
Nav.back();
assert.deepEqual(stack.getAllPathName(), [Routes.search], 'leaving the room returns to its actual source');
Nav.back();
Nav.openHistory(); Nav.openHistory();
assert.deepEqual(stack.getAllPathName(), [Routes.history]);
Nav.back(); Nav.openSettings(); Nav.openSettings();
assert.deepEqual(stack.getAllPathName(), [Routes.settings]);
Nav.back(); Nav.openAccount(); Nav.openAccount();
assert.deepEqual(stack.getAllPathName(), [Routes.account]);
Nav.back();
AppEnv.inst.reduceMotion = true;
const preview = LiveRoomItem.of('huya', 'three', 'fixture', '', 'fixture', 1);
Nav.openLive(preview, [10, 20, 160, 90]);
assert.equal('heroId' in stack.paths[0].param, false, 'the removed shared-hero parameter is not recreated');
assert.equal(stack.paths[0].param.preview, preview);
assert.deepEqual([stack.paths[0].param.coverX, stack.paths[0].param.coverY, stack.paths[0].param.coverW, stack.paths[0].param.coverH],
  [10, 20, 160, 90], 'the destination owns reduced motion; route geometry remains valid');
Nav.back();

const { C, Layout, Radius } = await import('../../entry/src/main/ets/theme/Theme');
assert.equal(Layout.bottomNavHeight, 56, 'dock stays slim while retaining 48vp button targets');
assert.equal(Layout.bottomNavMaxWidth, 380);
const { loadDockMaterial, DockMaterialModifier } = await import('../../entry/src/main/ets/platform/DockMaterial');
assert.equal(await loadDockMaterial(false), undefined);
assert.equal((globalThis as any).materialModuleLoads, undefined, 'API24 must never evaluate the new system-material module');
const attributes: Record<string, any> = {};
const legacyRow = {
  backgroundColor(value: any) { attributes.color = value; return this; },
  backgroundEffect(value: any) { attributes.effect = value; return this; },
  border(value: any) { attributes.border = value; attributes.radius = 0; return this; },
  borderWidth(value: any) { attributes.borderWidth = value; return this; },
  borderColor(value: any) { attributes.borderColor = value; return this; },
  borderRadius(value: any) { attributes.radius = value; return this; },
  shadow(value: any) { attributes.shadow = value; return this; }
};
new DockMaterialModifier(undefined).applyNormalAttribute(legacyRow as any);
assert.equal(attributes.color, '#00000000', 'no opaque fill may cover the background effect');
assert.equal(attributes.effect.adaptiveColor, 1);
assert.ok(attributes.effect.radius > 0);
for (const dark of [false, true]) {
  AppEnv.inst.isDark = dark;
  new DockMaterialModifier(undefined).applyNormalAttribute(legacyRow as any);
  const alpha = parseInt(attributes.effect.color.slice(1, 3), 16);
  assert.ok(alpha > 0 && alpha <= 128, 'both themes keep the dock tint at most half opaque');
  assert.equal(attributes.radius, Radius.pill, 'fallback border must preserve the capsule corners');
  assert.equal(attributes.effect.color, C.navSurface);
}
deviceInfo.sdkApiVersion = 26;
const material = await loadDockMaterial(false) as any;
assert.equal((globalThis as any).materialModuleLoads, 1);
assert.equal(material.options.interactive, false);
assert.deepEqual(material.options.lightEffect, { color: '#FFFFFF' });
const reduced = await loadDockMaterial(true) as any;
assert.equal(reduced.options.lightEffect, null);
let applied: any;
const modernRow = { ...legacyRow, systemMaterial(value: any) { applied = value; return this; } };
new DockMaterialModifier(material).applyNormalAttribute(modernRow as any);
assert.equal(applied, material);
assert.equal(attributes.radius, Radius.pill, 'resetting fallback borders cannot erase the system material radius');
assert.equal(attributes.effect, undefined, 'system material does not stack two backdrop filters');
const { materialState } = await import('./kit-material');
materialState.disabled = true;
assert.equal(await loadDockMaterial(false), undefined);
materialState.disabled = false; materialState.supported = false;
assert.equal(await loadDockMaterial(false), undefined);
materialState.supported = true; materialState.fail = true;
assert.equal(await loadDockMaterial(false), undefined, 'unavailable material service never breaks navigation');
console.log('Navigation/material: secondary routes, live replacement, reduced motion, API24 lazy gate/translucency and API26 fallback passed');
