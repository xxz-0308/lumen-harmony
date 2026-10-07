type Listener = (...args: unknown[]) => void;
class FakePlayer {
  state: string = 'idle';
  surfaceId: string = '';
  currentTime: number = 0;
  rejectBeforePlaying: boolean = false;
  rejectWithoutPlaying: boolean = false;
  deferPause: boolean = false;
  onReset: (() => void) | null = null;
  onSource: (() => void) | null = null;
  lastStrategy: Record<string, number | boolean> | undefined;
  private listeners: Map<string, Listener[]> = new Map<string, Listener[]>();

  on(event: string, fn: Listener): void {
    this.listeners.set(event, (this.listeners.get(event) ?? []).concat([fn]));
  }
  off(event: string): void { this.listeners.delete(event); }
  emit(event: string, ...args: unknown[]): void {
    for (const fn of this.listeners.get(event) ?? []) fn(...args);
  }
  async setMediaSource(_source?: string, strategy?: Record<string, number | boolean>): Promise<void> {
    this.lastStrategy = strategy;
    this.onSource?.();
    this.state = 'initialized';
    this.emit('stateChange', 'initialized');
  }
  async prepare(): Promise<void> {
    this.state = 'prepared';
    this.emit('stateChange', 'prepared');
  }
  async play(): Promise<void> {
    if (this.rejectWithoutPlaying) {
      this.rejectWithoutPlaying = false;
      throw { code: 5400103 };
    }
    if (this.rejectBeforePlaying) {
      this.rejectBeforePlaying = false;
      setTimeout(() => {
        this.state = 'playing';
        this.emit('stateChange', 'playing');
        this.emit('startRenderFrame');
      }, 0);
      throw { code: 5400103 };
    }
    this.state = 'playing';
    this.emit('stateChange', 'playing');
    this.emit('startRenderFrame');
  }
  async pause(): Promise<void> {
    if (this.deferPause) return;
    this.state = 'paused';
    this.emit('stateChange', 'paused');
  }
  async reset(): Promise<void> {
    this.onReset?.();
    this.state = 'idle';
    this.emit('stateChange', 'idle');
  }
  async release(): Promise<void> { this.state = 'released'; }
  setVolume(_value: number): void {}
}
export const native = new FakePlayer();
export const media = {
  BufferingInfoType: { BUFFERING_START: 1, BUFFERING_END: 2, CACHED_DURATION: 4 },
  createAVPlayer: async (): Promise<FakePlayer> => native,
  createMediaSourceWithUrl: (url: string): string => url
};
