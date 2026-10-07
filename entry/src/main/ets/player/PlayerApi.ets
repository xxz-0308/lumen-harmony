export enum PlayState {
  Idle = 0,
  Loading = 1,
  Playing = 2,
  Buffering = 3,
  Paused = 4,
  Error = 5
}

/** Which native engine renders a room. AVPlayer binds a surface ID; ijkplayer binds its own XComponent. */
export enum PlayerEngine {
  AvPlayer = 'avplayer',
  Ijk = 'ijk'
}

/** Everything the room model and pages use, so the engine can be swapped without touching them. */
export interface LivePlayerApi {
  readonly engine: PlayerEngine;
  state: PlayState;
  videoWidth: number;
  videoHeight: number;
  firstFrame: boolean;
  lineIndex: number;
  lineCount: number;
  errorText: string;
  notice: string;
  noticeSeq: number;
  reconnecting: boolean;
  autoSwitch: boolean;
  readonly wantsPlayback: boolean;
  /** How far the picture runs behind what the network has delivered (0 when unknown). */
  readonly latencyMs: number;
  onLinesExhausted: ((reason: string) => boolean) | null;
  onStreamEnded: (() => void) | null;
  onSuspended: (() => void) | null;
  onPlaying: (() => void) | null;

  /** AVPlayer only: the plain SURFACE XComponent's surface ID. */
  setSurface(id: string): void;
  /** ijkplayer only: the `ijkplayer_napi` XComponent's native context and component ID. */
  bindNative(context: object, id: string): void;
  /** ijkplayer only: that XComponent is being destroyed. */
  unbindNative(id: string): void;
  open(urls: string[], headers: Record<string, string>, startIndex?: number,
    seamless?: boolean, play?: boolean): Promise<void>;
  selectLine(index: number): void;
  retry(): void;
  giveUp(msg: string): void;
  pause(): void;
  resume(): void;
  setVolume(v: number): void;
  stop(): void;
  release(): void;
}
