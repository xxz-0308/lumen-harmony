import assert from 'node:assert/strict';
import { creations, FakePipController, PiPWindow } from './kit-pip';
import { LivePip } from '../../entry/src/main/ets/platform/LivePip';

const tick = async (): Promise<void> => { await Promise.resolve(); await Promise.resolve(); };
let plays = 0;
let pauses = 0;
const activity: [boolean, boolean][] = [];
const handlers = {
  play: () => { plays++; },
  pause: () => { pauses++; },
  onActive: (active: boolean, restoring: boolean) => { activity.push([active, restoring]); }
};
const pip = new LivePip(handlers);
pip.setAutoStart(true);
pip.setPlaying(true);
pip.attach({} as any, {} as any, 'test-navigation');
assert.deepEqual(creations[0].config.controlGroups, [401], 'live PiP requests play/pause controls');
pip.setContentSize(1920, 1080);
const controller = new FakePipController();
creations[0].resolve(controller);
await tick();
assert.equal(controller.autoStart, true);
assert.equal(controller.status, PiPWindow.PiPControlStatus.PLAY);
assert.deepEqual(controller.size, [1920, 1080], 'dimensions received while creating must reach the controller');
controller.emit('controlEvent', { controlType: 0, status: 0 });
controller.emit('controlEvent', { controlType: 0, status: 1 });
controller.emit('controlEvent', { controlType: 2, status: 0 });
controller.emit('controlEvent', { controlType: 0, status: 99 });
assert.equal(plays, 1);
assert.equal(pauses, 1, 'unrelated/unknown control events cannot pause the live stream');
controller.emit('stateChange', 1);
controller.emit('stateChange', 2);
controller.emit('stateChange', 5);
controller.emit('stateChange', 4);
assert.deepEqual(activity, [[true, false], [false, true]], 'restoring is not the same as closing PiP');
pip.dispose();
assert.equal(controller.autoStart, false);
assert.equal(controller.listeners.size, 0);

// A create completing after room disposal must not attach or arm a stale controller.
const disposed = new LivePip(handlers);
disposed.attach({} as any, {} as any, 'test-navigation');
disposed.dispose();
const stale = new FakePipController();
creations[1].resolve(stale);
await tick();
assert.equal(stale.stops, 1);
assert.equal(stale.listeners.size, 0);

// A start promise can finish after the user has already left the room.
const pending = new LivePip(handlers);
pending.attach({} as any, {} as any, 'test-navigation');
const late = new FakePipController();
creations[2].resolve(late);
await tick();
const starting = pending.start();
pending.dispose();
const stopsBeforeCompletion = late.stops;
late.finishStart!();
await starting;
assert.equal(late.stops, stopsBeforeCompletion + 1, 'late start must be stopped again after completion');
assert.equal(pending.active, false);

// Replacing a surface while its previous start is pending must not close the new controller.
const replacing = new LivePip(handlers);
replacing.attach({} as any, {} as any, 'test-navigation');
const old = new FakePipController();
creations[3].resolve(old);
await tick();
const oldStart = replacing.start();
replacing.attach({} as any, {} as any, 'test-navigation');
const current = new FakePipController();
creations[4].resolve(current);
await tick();
old.finishStart!();
await oldStart;
assert.equal(old.stops, 1);
assert.equal(current.stops, 0);
assert.equal(current.listeners.size, 2);
replacing.dispose();
console.log('LivePip: controls, restore, pending creation dimensions, disposal and late start isolation passed');
