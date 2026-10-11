type FrameCallback = (info: { timestamp: number }) => void;
let scopeCheck: (() => boolean) | null = null;
export function setScopeCheck(check: (() => boolean) | null): void { scopeCheck = check; }
function requireScope(): void { if (scopeCheck && !scopeCheck()) throw new Error('DisplaySync operation outside its owning UI context'); }
class FakeDisplaySync {
  running = false;
  callback: FrameCallback | null = null;
  range: { expected: number; min: number; max: number } | null = null;
  setExpectedFrameRateRange(range: { expected: number; min: number; max: number }): void { requireScope(); this.range = range; }
  on(_event: string, callback: FrameCallback): void { requireScope(); this.callback = callback; }
  off(_event: string): void { requireScope(); this.callback = null; }
  start(): void { requireScope(); this.running = true; }
  stop(): void { requireScope(); this.running = false; }
}
export const syncs: FakeDisplaySync[] = [];
export const displaySync = {
  create: (): FakeDisplaySync => {
    requireScope();
    const sync = new FakeDisplaySync();
    syncs.push(sync);
    return sync;
  }
};
export function emitFrame(timestamp: number): void {
  for (const sync of syncs) if (sync.running) sync.callback?.({ timestamp });
}
export function resetSyncs(): void { syncs.length = 0; }
