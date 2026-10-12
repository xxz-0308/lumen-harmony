import assert from 'node:assert/strict';
import { FrameCallback } from './kit-arkui';
import { RoomMount } from '../../entry/src/main/ets/room/RoomMount';

const pending: FrameCallback[] = [];
const context = { postFrameCallback: (callback: FrameCallback) => { pending.push(callback); } };
const frame = () => {
  const tasks = pending.splice(0);
  for (const task of tasks) task.onIdle(4_000_000);
};
const mount = new RoomMount();
const stages: number[] = [];
mount.start(context as never, stage => stages.push(stage));
assert.deepEqual(stages, [], 'destination mount only schedules work, not synchronous child construction');
for (let stage = 0; stage < 6; stage++) {
  frame();
  assert.deepEqual(stages, Array.from({ length: stage + 1 }, (_, i) => i), 'each layer gets a separate idle frame');
}
assert.equal(pending.length, 0);

mount.start(context as never, stage => stages.push(stage + 10));
mount.cancel(); frame();
assert.deepEqual(stages, [0, 1, 2, 3, 4, 5], 'a quick Back cannot mount content in the retiring room');
mount.start(context as never, stage => stages.push(stage + 20));
frame(); mount.cancel(); frame();
assert.deepEqual(stages, [0, 1, 2, 3, 4, 5, 20], 'disposal cancels the remainder after surface creation');

mount.start(context as never, stage => stages.push(stage + 30));
mount.start(context as never, stage => stages.push(stage + 40));
for (let i = 0; i < 6; i++) frame();
assert.deepEqual(stages.slice(-6), [40, 41, 42, 43, 44, 45], 'only the latest mount sequence can publish');
mount.start(context as never, () => mount.cancel());
frame(); assert.equal(pending.length, 0, 'cancellation inside a callback schedules no next stage');
let freed = false;
RoomMount.afterPaint(context as never, () => { freed = true; });mount.cancel();
assert.equal(freed, false);frame();assert.equal(freed, true, 'resource cleanup outlives cancelled mounting but runs after paint');
console.log('Room mount: separate idle frames, quick Back, disposal, stale sequences and after-paint cleanup passed');
