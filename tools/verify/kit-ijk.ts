// Fake @ohos/ijkplayer: records native calls across instances so tests can check ordering.
export enum VideoCodecMode { BUFFER = 0, SURFACE = 1 }
export enum InterruptHintType {
  INTERRUPT_HINT_NONE = 0, INTERRUPT_HINT_RESUME = 1, INTERRUPT_HINT_PAUSE = 2,
  INTERRUPT_HINT_STOP = 3, INTERRUPT_HINT_DUCK = 4, INTERRUPT_HINT_UNDUCK = 5
}
export interface InterruptEvent { forceType?: number; hintType?: InterruptHintType; reason?: number }
export interface OnPreparedListener { onPrepared: () => void }
export interface OnInfoListener { onInfo: (what: number, extra: number) => void }
export interface OnErrorListener { onError: (what: number, extra: number) => void }
export interface OnCompletionListener { onCompletion: () => void }
export interface OnVideoSizeChangedListener {
  onVideoSizeChanged: (w: number, h: number, sarNum: number, sarDen: number) => void
}

export const ops: string[] = [];
export const players: IjkMediaPlayer[] = [];

export class IjkMediaPlayer {
  static OPT_CATEGORY_FORMAT: string = '1';
  static OPT_CATEGORY_PLAYER: string = '4';
  id: string;
  options: Map<string, string> = new Map<string, string>();
  url: string = '';
  volume: string = '';
  released: boolean = false;
  prepared?: OnPreparedListener;
  info?: OnInfoListener;
  error?: OnErrorListener;
  completion?: OnCompletionListener;
  size?: OnVideoSizeChangedListener;
  interrupt?: (e: InterruptEvent) => void;
  cachedMs: number = 4000;

  constructor(id: string = '') {
    this.id = id;
    players.push(this);
  }
  setContext(_context: object, id: string): void { this.id = id; }
  native_setup(mode: VideoCodecMode = VideoCodecMode.BUFFER): void { ops.push(`setup:${this.id}:${mode}`); }
  setOption(category: string, key: string, value: string): void { this.options.set(`${category}/${key}`, value); }
  setOptionLong(category: string, key: string, value: string): void { this.options.set(`${category}/${key}`, value); }
  setDataSource(url: string): void { this.url = url; }
  setDataSourceHeader(headers: Map<string, string>): void { this.options.set('headers', [...headers.keys()].join(',')); }
  setOnPreparedListener(l: OnPreparedListener): void { this.prepared = l; }
  setOnInfoListener(l: OnInfoListener): void { this.info = l; }
  setOnErrorListener(l: OnErrorListener): void { this.error = l; }
  setOnCompletionListener(l: OnCompletionListener): void { this.completion = l; }
  setOnVideoSizeChangedListener(l: OnVideoSizeChangedListener): void { this.size = l; }
  on(_type: string, cb: (e: InterruptEvent) => void): void { this.interrupt = cb; }
  off(_type: string): void { this.interrupt = undefined; }
  setMessageListener(): void {}
  setDebug(_open: boolean): void {}
  prepareAsync(): void { ops.push(`prepare:${this.url}`); }
  start(): void { ops.push(`start:${this.url}`); }
  pause(): void { ops.push(`pause:${this.url}`); }
  setVolume(left: string, _right: string): void { this.volume = left; }
  setSpeed(speed: string): void { ops.push(`speed:${speed}`); }
  async stopAsync(): Promise<boolean> { ops.push(`stop:${this.url}`); return true; }
  async releaseAsync(): Promise<boolean> {
    this.released = true;
    ops.push(`release:${this.url}`);
    return true;
  }
  getVideoDecoder(): number { return 2; }
  getVideoCachedDuration(): number { return this.cachedMs; }
  getAudioCachedDuration(): number { return this.cachedMs; }
  getVideoCachedBytes(): number { return 1000; }
  getTcpSpeed(): number { return 300000; }
  getVideoDecodeFramesPerSecond(): number { return 60; }
  getVideoOutputFramesPerSecond(): number { return 60; }
  getDropFrameRate(): number { return 0; }

  /** Test helpers: what the native message thread would deliver. */
  emitPrepared(): void { this.prepared?.onPrepared(); }
  emitInfo(what: number, extra: number = 0): void { this.info?.onInfo(what, extra); }
  emitError(what: number, extra: number = 0): void { this.error?.onError(what, extra); }
  emitCompletion(): void { this.completion?.onCompletion(); }
}

export function latest(): IjkMediaPlayer {
  return players[players.length - 1];
}
