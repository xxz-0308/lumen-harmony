export interface TestPixelMap {
  width: number;
  height: number;
  released: boolean;
  release(): void;
}
export const imageStats = { sources: 0, sourceReleases: 0, pixels: [] as TestPixelMap[], failDecode: false };
export const image = {
  createImageSource: (_buffer: ArrayBuffer) => {
    imageStats.sources++;
    return {
      createPixelMap: async (options?: { desiredSize?: { width: number; height: number } }): Promise<TestPixelMap> => {
        if (imageStats.failDecode) { imageStats.failDecode = false; throw new Error('fixture decode failure'); }
        const pm: TestPixelMap = {
          width: options?.desiredSize?.width ?? 160,
          height: options?.desiredSize?.height ?? 160,
          released: false,
          release() { this.released = true; }
        };
        imageStats.pixels.push(pm);
        return pm;
      },
      release: (): void => { imageStats.sourceReleases++; }
    };
  }
};
