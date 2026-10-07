export const motionListeners = new Set<(enabled: boolean) => void>();
export let motionReduced = false;
export function setMotionReduced(enabled: boolean): void {
  motionReduced = enabled;
  motionListeners.forEach((listener) => listener(enabled));
}
export const accessibility = {
  isAnimationReduceEnabledSync: (): boolean => motionReduced,
  onAnimationReduceStateChange: (listener: (enabled: boolean) => void): void => { motionListeners.add(listener); },
  offAnimationReduceStateChange: (listener: (enabled: boolean) => void): void => { motionListeners.delete(listener); }
};
