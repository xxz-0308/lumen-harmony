import { display, window } from '@kit.ArkUI';

export enum VideoFullscreenMode {
  None = 0,
  Floating = 1,
  Immersive = 2
}

export class VideoFullscreenSession {
  win: window.Window;
  id: number;
  displayId: number | undefined;
  originalRect: window.Rect;
  priorOrientation: window.Orientation;
  priorImmersive: boolean;
  floating: boolean;
  appliedRect: window.Rect | null = null;
  geometryChanged: boolean = false;
  resizing: boolean = false;

  constructor(win: window.Window, floating: boolean, immersive: boolean) {
    const props = win.getWindowProperties();
    this.win = win;
    this.id = props.id;
    this.displayId = props.displayId;
    this.originalRect = copyWindowRect(props.windowRect);
    this.priorOrientation = win.getPreferredOrientation();
    this.priorImmersive = immersive;
    this.floating = floating;
  }
}

export function copyWindowRect(rect: window.Rect): window.Rect {
  return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
}

export function sameWindowRect(a: window.Rect, b: window.Rect): boolean {
  return a.left === b.left && a.top === b.top && a.width === b.width && a.height === b.height;
}

/** Native pixels only. Keep the current top-left corner and never grow to tablet fullscreen. */
export function floatingVideoSize(rect: window.Rect, limits: window.WindowLimits,
  screen: display.Display, aspect: number): window.Size {
  if (!Number.isFinite(aspect) || aspect <= 0) {
    throw new Error('Invalid video aspect ratio');
  }
  // A portrait stream still gets a landscape video-only window, with the video fitted inside it.
  const ratio = aspect > 1 ? aspect : 16 / 9;
  const maxWidth = Math.floor(Math.min(limits.maxWidth ?? screen.availableWidth,
    screen.availableWidth, screen.width - Math.max(0, rect.left)));
  const maxHeight = Math.floor(Math.min(limits.maxHeight ?? screen.availableHeight,
    screen.availableHeight, screen.height - Math.max(0, rect.top)));
  const minWidth = Math.ceil(Math.max(1, limits.minWidth ?? 1));
  const minHeight = Math.ceil(Math.max(1, limits.minHeight ?? 1));
  const low = Math.ceil(Math.max(minHeight, minWidth / ratio));
  const high = Math.floor(Math.min(maxHeight, maxWidth / ratio));
  if (!Number.isFinite(low) || !Number.isFinite(high) || low > high) {
    throw new Error('Floating window limits do not permit a landscape video window');
  }
  const height = Math.max(low, Math.min(high, Math.round(Math.max(rect.width, rect.height) / ratio)));
  const width = Math.round(height * ratio);
  if (width <= height || width < minWidth || width > maxWidth) {
    throw new Error('Floating window limits do not permit a landscape video window');
  }
  return { width: width, height: height };
}
