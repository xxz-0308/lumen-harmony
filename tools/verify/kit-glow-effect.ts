import { TestPixelMap } from './kit-image';
export const glowStats = { pixels: [] as TestPixelMap[], failBlur: false };
export const effectKit = {
  TileMode: { CLAMP: 0 },
  createEffect: (small: TestPixelMap) => ({
    blur: (radius: number, mode: number) => ({
      getEffectPixelMap: async (): Promise<TestPixelMap> => {
        if (glowStats.failBlur) { glowStats.failBlur = false; throw new Error('fixture blur failure'); }
        if (radius !== 6 || mode !== 0) throw new Error('unexpected glow settings');
        const pm: TestPixelMap = { width: small.width, height: small.height, released: false,
          release() { this.released = true; } };
        glowStats.pixels.push(pm);
        return pm;
      }
    })
  })
};
