export class FrameCallback {
  onFrame(_time: number): void {}
  onIdle(_time: number): void {}
}
export const display = {};
export const window = {
  AvoidAreaType: { TYPE_SYSTEM: 0, TYPE_NAVIGATION_INDICATOR: 4, TYPE_KEYBOARD: 3 },
  WindowStatusType: { UNDEFINED: 0, FULL_SCREEN: 1, MAXIMIZE: 2, MINIMIZE: 3, FLOATING: 4, SPLIT_SCREEN: 5 }
};
export const curves = {
  springMotion: (..._args: number[]) => ({}),
  interpolatingSpring: (..._args: number[]) => ({})
};
