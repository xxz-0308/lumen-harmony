import assert from 'node:assert/strict';
import { motionListeners, setMotionReduced } from './kit-accessibility';

Object.assign(globalThis, {
  ObservedV2: (value: unknown): unknown => value,
  Trace: (): void => {}
});
const { AppEnv } = await import('../../entry/src/main/ets/app/AppEnv');
const events: boolean[] = [];
const listener = (): void => { events.push(AppEnv.inst.foreground); };
AppEnv.inst.subscribeForeground(listener);
AppEnv.setWindowVisible(false);
assert.equal(AppEnv.inst.foreground, false);
AppEnv.setAbilityForeground(false);
AppEnv.setAbilityForeground(true);
assert.equal(AppEnv.inst.foreground, false, 'ability foreground cannot override hidden main window');
AppEnv.setWindowVisible(true);
assert.equal(AppEnv.inst.foreground, true);
AppEnv.setAbilityForeground(false);
AppEnv.setWindowVisible(false);
AppEnv.setWindowVisible(true);
assert.equal(AppEnv.inst.foreground, false, 'window visibility cannot override background ability');
AppEnv.setAbilityForeground(true);
assert.equal(AppEnv.inst.foreground, true);
assert.deepEqual(events, [false, true, false, true]);
AppEnv.inst.unsubscribeForeground(listener);
AppEnv.setWindowVisible(false);
assert.equal(events.length, 4);
AppEnv.setWindowVisible(true);
setMotionReduced(true);
// Window APIs are deliberately absent: accessibility setup must not depend on window setup succeeding.
AppEnv.attachWindow({} as never);
assert.equal(AppEnv.inst.reduceMotion, true);
assert.equal(motionListeners.size, 1);
AppEnv.attachWindow({} as never);
assert.equal(motionListeners.size, 1, 'window reattachment does not duplicate the named listener');
setMotionReduced(false);
assert.equal(AppEnv.inst.reduceMotion, false);
AppEnv.detachWindow();
assert.equal(motionListeners.size, 0);
setMotionReduced(true);
assert.equal(AppEnv.inst.reduceMotion, false, 'detached window does not receive animation changes');
console.log('AppEnv: foreground arbitration, system reduced motion and listener cleanup passed');
