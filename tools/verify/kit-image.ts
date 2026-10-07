export const image = {
  createImageSource: (_buffer: ArrayBuffer) => ({
    createPixelMap: async (): Promise<object> => ({ width: 160, height: 160 }),
    release: (): void => {}
  })
};
