import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { HttpRequest, Platform } from '../core/common/Transport';
import { Log } from './Log';

/**
 * Ambient glows are a cover blurred beyond recognition. Blurring a tiny decode once and letting
 * the GPU stretch it preserves the soft cover colours without a full-window filter on every
 * frame. The glow can sit under page transitions and fades without forcing a live re-blur.
 */
export class GlowLoader {
  private static cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static pending: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();
  private static readonly MAX: number = 24;

  static cached(url: string): image.PixelMap | null {
    return GlowLoader.cache.get(url) ?? null;
  }

  static load(url: string): Promise<image.PixelMap | null> {
    const hit = GlowLoader.cache.get(url);
    if (hit !== undefined) {
      return Promise.resolve(hit);
    }
    const inflight = GlowLoader.pending.get(url);
    if (inflight !== undefined) {
      return inflight;
    }
    const task = GlowLoader.bake(url).finally(() => GlowLoader.pending.delete(url));
    GlowLoader.pending.set(url, task);
    return task;
  }

  private static async bake(url: string): Promise<image.PixelMap | null> {
    try {
      const req = new HttpRequest();
      req.url = url;
      req.binary = true;
      req.timeoutMs = 10000;
      const res = await Platform.http.send(req);
      if (res.status !== 200 || res.bytes.length === 0) {
        return null;
      }
      const b = res.bytes;
      const src = image.createImageSource(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer);
      let small: image.PixelMap;
      try {
        small = await src.createPixelMap({ desiredSize: { width: 64, height: 36 } });
      } finally {
        src.release();
      }
      let glow: image.PixelMap;
      try {
        glow = await effectKit.createEffect(small).blur(6, effectKit.TileMode.CLAMP).getEffectPixelMap();
      } finally {
        small.release();
      }
      if (GlowLoader.cache.size >= GlowLoader.MAX) {
        const first = GlowLoader.cache.keys().next();
        if (!first.done) {
          // A mounted glow may still draw it; the PixelMap is released with its last reference.
          GlowLoader.cache.delete(first.value);
        }
      }
      GlowLoader.cache.set(url, glow);
      return glow;
    } catch (e) {
      Log.w('image', `glow bake failed ${url.split('?')[0]}`);
      return null;
    }
  }
}
