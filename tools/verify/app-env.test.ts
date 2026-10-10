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
AppEnv.init({ config: { colorMode: 0, fontSizeScale: 1.5 } } as never);
assert.equal(AppEnv.inst.fontScale, 1.5);
AppEnv.syncSystemColorMode({ colorMode: 0, fontSizeScale: 2 } as never); assert.equal(AppEnv.inst.fontScale, 2);
const callbacks = new Map<string, (...args: any[]) => void>(); let keyboardPixels = 400;
const win = {
  setWindowLayoutFullScreen() {}, setWindowSystemBarProperties() {},
  on(name: string, callback: (...args: any[]) => void) { callbacks.set(name, callback); },
  off(name: string) { callbacks.delete(name); },
  getWindowProperties: () => ({ windowRect: { width: 2400, height: 1600 } }),
  getWindowAvoidArea: (type: number) => ({ topRect: { height: type === 0 ? 48 : 0 },
    bottomRect: { height: type === 3 ? keyboardPixels : type === 4 ? 24 : 0 } })
};
AppEnv.attachWindow(win as never); assert.equal(AppEnv.inst.keyboardHeight, 0);
callbacks.get('keyboardHeightChange')!(400); assert.equal(AppEnv.inst.keyboardHeight, 200);
keyboardPixels = 0; callbacks.get('avoidAreaChange')!();
assert.equal(AppEnv.inst.keyboardHeight, 200, 'a generic avoid-area notification must not clear the authoritative keyboard height');
callbacks.get('keyboardHeightChange')!(0); assert.equal(AppEnv.inst.keyboardHeight, 0);
AppEnv.detachWindow(); assert.equal(AppEnv.inst.keyboardHeight, 0); assert.equal(callbacks.size, 0);
console.log('AppEnv: foreground/motion ownership, font configuration and keyboard avoid-area cleanup passed');
