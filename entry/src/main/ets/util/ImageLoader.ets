import { image } from '@kit.ImageKit';
import { HttpRequest, Platform } from '../core/common/Transport';
import { Log } from './Log';

/**
 * Some CDNs (Douyu avatars) serve PNG bytes labelled image/jpeg, which the system Image
 * loader refuses. For those hosts we download and decode ourselves; the decoder sniffs the
 * real format from the bytes.
 */
export class ImageLoader {
  private static cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  /** Briefly suppress repeated failures without permanently blacklisting a recovered CDN URL. */
  private static failed: Map<string, number> = new Map<string, number>();
  private static pending: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();
  private static active: number = 0;
  private static queue: (() => void)[] = [];
  private static readonly MAX_ACTIVE: number = 8;
  private static readonly MAX: number = 160;

  static needsManual(url: string): boolean {
    return url.indexOf('apic.douyucdn.cn') >= 0;
  }

  static cached(url: string): image.PixelMap | null {
    return ImageLoader.cache.get(url) ?? null;
  }

  static load(url: string): Promise<image.PixelMap | null> {
    const hit = ImageLoader.cache.get(url);
    if (hit !== undefined) {
      return Promise.resolve(hit);
    }
    if ((ImageLoader.failed.get(url) ?? 0) > Date.now()) {
      return Promise.resolve(null);
    }
    ImageLoader.failed.delete(url);
    const inflight = ImageLoader.pending.get(url);
    if (inflight !== undefined) {
      return inflight;
    }
    const task = ImageLoader.enqueue(url);
    ImageLoader.pending.set(url, task);
    return task;
  }

  private static enqueue(url: string): Promise<image.PixelMap | null> {
    return new Promise<image.PixelMap | null>((resolve: (value: image.PixelMap | null) => void) => {
      const start = (): void => {
        ImageLoader.active++;
        ImageLoader.fetch(url).then(resolve).finally(() => {
          ImageLoader.active--;
          ImageLoader.pending.delete(url);
          ImageLoader.drain();
        });
      };
      ImageLoader.queue.push(start);
      ImageLoader.drain();
    });
  }

  private static drain(): void {
    while (ImageLoader.active < ImageLoader.MAX_ACTIVE && ImageLoader.queue.length > 0) {
      const next = ImageLoader.queue.shift();
      next?.();
    }
  }

  private static markFailed(url: string): void {
    if (ImageLoader.failed.size >= ImageLoader.MAX) {
      const first = ImageLoader.failed.keys().next();
      if (!first.done) {
        ImageLoader.failed.delete(first.value);
      }
    }
    ImageLoader.failed.set(url, Date.now() + 30000);
  }

  private static async fetch(url: string): Promise<image.PixelMap | null> {
    try {
      const req = new HttpRequest();
      req.url = url;
      req.binary = true;
      req.timeoutMs = 10000;
      const res = await Platform.http.send(req);
      if (res.status !== 200 || res.bytes.length === 0) {
        ImageLoader.markFailed(url);
        return null;
      }
      const b = res.bytes;
      const buf = b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer;
      const src = image.createImageSource(buf);
      let pm: image.PixelMap;
      try {
        pm = await src.createPixelMap({ desiredSize: { width: 160, height: 160 } });
      } finally {
        src.release();
      }
      if (ImageLoader.cache.size >= ImageLoader.MAX) {
        const first = ImageLoader.cache.keys().next();
        if (!first.done) {
          // A mounted NetImage may still hold the PixelMap; release only when its last owner is gone.
          ImageLoader.cache.delete(first.value);
        }
      }
      ImageLoader.cache.set(url, pm);
      return pm;
    } catch (e) {
      Log.w('image', `manual load failed ${url.split('?')[0]}`);
      ImageLoader.markFailed(url);
      return null;
    }
  }
}
