import assert from 'node:assert/strict';
import { layoutRoomSheet, RoomSheetBounds, SheetKind } from '../../entry/src/main/ets/room/RoomSheetLayout';

const normal: RoomSheetBounds = { kind: 'quality', width: 1200, height: 800, topInset: 32, navInset: 24, anchorX: 900, anchorY: 700 };
const quality = layoutRoomSheet(normal);
assert.deepEqual([quality.width, quality.x, quality.bottom, quality.maxH, quality.headerH, quality.bodyH], [300, 750, 670, 480, 52, 418]);
const follows = layoutRoomSheet({ ...normal, kind: 'follows' });
assert.deepEqual([follows.width, follows.x, follows.y, follows.maxH, follows.bodyH], [380, 808, 32, 732, 680]);
assert.equal(layoutRoomSheet({ ...normal, kind: 'danmaku' }).width, 380);
const keyboard = layoutRoomSheet({ ...normal, kind: 'sleep', keyboardHeight: 350, windowHeight: 800 });
assert.equal(keyboard.bottom, 426); assert.equal(keyboard.bodyH, 208);
assert.deepEqual(layoutRoomSheet({ ...normal, height: 450, kind: 'sleep', keyboardHeight: 350, windowHeight: 800 }), keyboard,
  'a resized root does not subtract keyboard height twice');
const large = layoutRoomSheet({ ...normal, fontScale: 2 }); assert.equal(large.rowH, 104); assert.ok(large.headerH >= 52);
for (const kind of ['quality', 'line', 'danmaku', 'follows', 'sleep'] as SheetKind[]) {
  for (const width of [280, 360, 900, 1200]) for (const height of [240, 400, 800]) {
    for (const keyboardHeight of [0, 100, 200]) for (const fontScale of [1, 1.5, 2]) {
      const input = { ...normal, kind, width, height, windowHeight: height, keyboardHeight, fontScale };
      const layout = layoutRoomSheet(input); const available = Math.max(0, height - keyboardHeight);
      assert.ok(layout.x >= 0 && layout.x + layout.width <= width);
      assert.ok(layout.maxH >= 0 && layout.bodyH >= 0 && layout.headerH >= 0);
      assert.ok(layout.bottom <= available && layout.y + layout.maxH <= available);
      assert.ok(layout.headerH <= layout.maxH && layout.bodyH <= layout.maxH);
    }
  }
}
console.log('Room sheets: ordinary geometry preserved, keyboard/root resize, font scale and bounded short-window layout passed');
