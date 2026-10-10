import { isNarrowTheater } from './TheaterLayout';

export type SheetKind = '' | 'quality' | 'line' | 'danmaku' | 'follows' | 'sleep';

export interface RoomSheetBounds {
  kind: SheetKind;
  width: number;
  height: number;
  topInset: number;
  navInset: number;
  anchorX: number;
  anchorY: number;
  fontScale?: number;
  keyboardHeight?: number;
  windowHeight?: number;
}

export class RoomSheetLayout {
  width: number = 0;
  x: number = 0;
  y: number = 0;
  bottom: number = 0;
  maxH: number = 0;
  headerH: number = 52;
  bodyH: number = 0;
  rowH: number = 52;
  side: boolean = false;
}

/** Presentation only: no room actions, playback ownership or timer policy lives here. */
export function layoutRoomSheet(bounds: RoomSheetBounds): RoomSheetLayout {
  const result = new RoomSheetLayout();
  const width = Math.max(0, bounds.width);
  const height = Math.max(0, Math.min(bounds.height, (bounds.windowHeight ?? bounds.height) - (bounds.keyboardHeight ?? 0)));
  const gutter = Math.min(12, width / 2);
  const top = Math.min(Math.max(0, bounds.topInset), height);
  const scale = Math.max(1, bounds.fontScale ?? 1);
  result.headerH = Math.max(52, Math.ceil(28 * scale));
  result.rowH = Math.ceil(52 * scale);
  result.side = bounds.kind === 'follows';
  if (result.side) {
    result.width = Math.min(380, isNarrowTheater(width) ? Math.max(0, width - gutter * 2) : width * 0.4);
    result.x = Math.max(0, width - result.width - gutter);
    result.y = top;
    result.maxH = Math.max(0, height - top - 12 - bounds.navInset);
    result.bottom = top + result.maxH;
    result.headerH = Math.min(result.headerH, result.maxH);
    result.bodyH = Math.max(0, result.maxH - result.headerH);
  } else {
    result.width = Math.min(bounds.kind === 'danmaku' ? 380 : 300, Math.max(0, width - gutter * 2));
    const center = bounds.anchorX > 0 ? bounds.anchorX : width / 2;
    result.x = Math.max(gutter, Math.min(center - result.width / 2, width - result.width - gutter));
    const desired = bounds.anchorY > 0 ? bounds.anchorY - 30 : height - 96;
    const limit = Math.max(top, height - 24);
    result.bottom = Math.max(Math.min(top + 160, limit), Math.min(desired, limit));
    // The usual 60% cap remains; short windows may use the available space for one usable row.
    result.maxH = Math.max(0, Math.min(Math.max(height * 0.6, result.headerH + 54), result.bottom - top));
    result.headerH = Math.min(result.headerH, result.maxH);
    result.bodyH = Math.max(0, result.maxH - result.headerH - 10);
  }
  return result;
}
