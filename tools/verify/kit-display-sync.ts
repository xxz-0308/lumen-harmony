type FrameCallback = (info: { timestamp: number }) => void;
class FakeDisplaySync {
  running = false;
  callback: FrameCallback | null = null;
  range: { expected: number; min: number; max: number } | null = null;
  setExpectedFrameRateRange(range: { expected: number; min: number; max: number }): void { this.range = range; }
  on(_event: string, callback: FrameCallback): void { this.callback = callback; }
  off(_event: string): void { this.callback = null; }
  start(): void { this.running = true; }
  stop(): void { this.running = false; }
}
export const syncs: FakeDisplaySync[] = [];
export const displaySync = {
  create: (): FakeDisplaySync => {
    const sync = new FakeDisplaySync();
    syncs.push(sync);
    return sync;
  }
};
export function emitFrame(timestamp: number): void {
  for (const sync of syncs) if (sync.running) sync.callback?.({ timestamp });
}
export function resetSyncs(): void { syncs.length = 0; }
