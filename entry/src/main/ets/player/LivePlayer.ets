import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../util/Log';
import { BufferStats } from './BufferStats';
import { LivePlayerApi, PlayerEngine, PlayState } from './PlayerApi';

export { PlayState } from './PlayerApi';

const STALL_SWITCH_MS = 9000;
const START_TIMEOUT_MS = 12000;
/** Position watchdog: catches a frozen picture that never raises a buffering event. */
const WATCHDOG_MS = 5000;
const WATCHDOG_STRIKES = 2;
const BUFFER_SUMMARY_MS = 30000;

/**
 * AVPlayer wrapper for live streams: ordered line failover, stall watchdog and first-frame signal.
 * One instance lives for a room page; `open()` can be called repeatedly to switch source.
 */
@ObservedV2
export class LivePlayer implements LivePlayerApi {
  readonly engine: PlayerEngine = PlayerEngine.AvPlayer;
  @Trace state: PlayState = PlayState.Idle;
  @Trace videoWidth: number = 16;
  @Trace videoHeight: number = 9;
  @Trace firstFrame: boolean = false;
  @Trace lineIndex: number = 0;
  @Trace lineCount: number = 0;
  @Trace errorText: string = '';
  @Trace volume: number = 1;
  /** Human-readable notice for transient events (auto line switch). */
  @Trace notice: string = '';
  @Trace noticeSeq: number = 0;

  autoSwitch: boolean = true;
  private player: media.AVPlayer | null = null;
  private creating: Promise<media.AVPlayer> | null = null;
  private surfaceId: string = '';
  private urls: string[] = [];
  private headers: Record<string, string> = {};
  private session: number = 0;
  private stallTimer: number = -1;
  private startTimer: number = -1;
  private wantPlay: boolean = true;
  private triedInSession: number = 0;
  /** Every line failed; return true if the owner will recover (e.g. re-resolve URLs). */
  onLinesExhausted: ((reason: string) => boolean) | null = null;
  /** Called when the server ends a live stream; the owner should re-resolve URLs and `open(..., true)`. */
  onStreamEnded: (() => void) | null = null;
  /** A paused stream lost its connection; the owner must re-resolve URLs before resuming. */
  onSuspended: (() => void) | null = null;
  /** Playback actually started; the owner can clear a stale error overlay. */
  onPlaying: (() => void) | null = null;
  private seamless: boolean = false;
  private gotFrame: boolean = false;
  private resetting: boolean = false;
  /** Native reset and source assignment must not race between a refresh, failover and stop. */
  private sourceOps: Promise<void> = Promise.resolve();
  private watchdogTimer: number = -1;
  private lastPosition: number = -1;
  private stalledChecks: number = 0;
  private bufferStats: BufferStats = new BufferStats();
  private bufferSummaryTimer: number = -1;
  private playbackInfoPending: boolean = false;
  /** Assignment epoch, not recovery session. Native callbacks do not carry their own source ID. */
  private sourceEpoch: number = 0;
  /** Released players never create another AVPlayer (the room page is gone). */
  private released: boolean = false;

  setSurface(id: string): void {
    this.surfaceId = id;
    const p = this.player;
    if (p !== null && p.state === 'initialized') {
      p.surfaceId = id;
      p.prepare().catch((e: BusinessError) => this.fail(`prepare ${e.code}`));
    }
  }

  bindNative(_context: object, _id: string): void {
  }

  unbindNative(_id: string): void {
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player !== null) {
      return this.player;
    }
    if (this.creating === null) {
      this.creating = media.createAVPlayer().then((p: media.AVPlayer) => {
        if (this.released) {
          // The page was closed while native player creation was still pending.
          p.release().catch(() => {
          });
          return p;
        }
        this.bind(p);
        this.player = p;
        return p;
      }).catch(() => {
        // A transient native creation failure must not poison every later retry.
        this.creating = null;
        throw new Error('AVPlayer creation failed');
      });
    }
    return this.creating;
  }

  private bind(p: media.AVPlayer): void {
    p.on('stateChange', (st: media.AVPlayerState) => {
      Log.i('player', `state ${st}`);
      switch (st) {
        case 'initialized':
          if (this.surfaceId.length > 0) {
            p.surfaceId = this.surfaceId;
            p.prepare().catch((e: BusinessError) => this.fail(`prepare ${e.code}`));
          }
          break;
        case 'prepared':
          if (this.state === PlayState.Idle || this.state === PlayState.Error || this.released || this.resetting) {
            break;
          }
          p.setVolume(this.volume);
          if (this.wantPlay) {
            const session = this.session;
            p.play().catch((e: BusinessError) => {
              // On this device a PiP surface returning to the app can reject play while the
              // native player reports "playing" on the following tick. Check its settled state.
              setTimeout(() => {
                if (session === this.session && this.wantPlay && !this.released && p.state !== 'playing') {
                  this.nextLine(`播放出错（${e.code}）`);
                }
              }, 250);
            });
          } else {
            this.state = PlayState.Paused;
          }
          break;
        case 'playing':
          if (this.resetting) {
            break;
          }
          if (this.released || !this.wantPlay || this.state === PlayState.Idle || this.state === PlayState.Error) {
            p.pause().catch(() => {});
            break;
          }
          this.state = PlayState.Playing;
          this.reconnecting = false;
          this.clearStall();
          this.armWatchdog();
          this.bufferStats.expose(this.gotFrame, Date.now());
          this.onPlaying?.();
          break;
        case 'paused':
          this.interruptBuffer('native-paused');
          if (this.state !== PlayState.Error && this.state !== PlayState.Idle) {
            this.state = PlayState.Paused;
          }
          this.clearWatchdog();
          break;
        case 'completed':
          // A prior source can finish as reset tears it down; it is not a new stream failure.
          if (this.resetting || this.state === PlayState.Idle || this.state === PlayState.Error) {
            break;
          }
          this.interruptBuffer('completed');
          // a live stream "completing" means the CDN cut us off (e.g. signed URL expired)
          if (!this.wantPlay) {
            this.suspend();
          } else if (this.onStreamEnded !== null) {
            this.onStreamEnded();
          } else {
            this.nextLine('直播流中断');
          }
          break;
        default:
          break;
      }
    });
    p.on('error', (err: BusinessError) => {
      if (this.resetting || this.released || this.state === PlayState.Idle || this.state === PlayState.Error) {
        Log.i('player', `ignored inactive-source error ${err.code}`);
        return;
      }
      Log.w('player', `error ${err.code}`);
      this.nextLine(`播放出错（${err.code}）`);
    });
    p.on('bufferingUpdate', (type: media.BufferingInfoType, value: number) => {
      // Observe EVERY native START/END before UI guards; cache updates never log individually.
      const now = Date.now();
      if (type === media.BufferingInfoType.CACHED_DURATION) {
        this.bufferStats.cache(value, now);
        return;
      }
      if (type === media.BufferingInfoType.BUFFERING_START) {
        this.logBuffer(`START ${this.bufferStats.start(now)}`, now);
        this.samplePlaybackInfo();
      } else if (type === media.BufferingInfoType.BUFFERING_END) {
        this.logBuffer(`END ${this.bufferStats.end(now)}`, now);
      } else {
        return;
      }
      if (!this.wantPlay || this.resetting || this.released ||
        this.state === PlayState.Idle || this.state === PlayState.Error) {
        return;
      }
      if (type === media.BufferingInfoType.BUFFERING_START) {
        if (this.state === PlayState.Playing) {
          this.state = PlayState.Buffering;
          this.clearWatchdog();
          this.armStall();
        }
      } else {
        if (this.state === PlayState.Buffering && p.state === 'playing') {
          this.state = PlayState.Playing;
          // START may have removed the position timer. Duplicate/orphan END must not reset it.
          this.armWatchdog();
        }
        this.clearStall();
      }
    });
    p.on('speedDone', (mode: number) => {
      // FLV automatic catch-up reports mode 100 (1.2x); this is not an app setSpeed request.
      this.logBuffer(`SPEED mode=${mode} positionMs=${p.currentTime}`, Date.now());
    });
    p.on('videoSizeChange', (w: number, h: number) => {
      if (w > 0 && h > 0) {
        this.videoWidth = w;
        this.videoHeight = h;
      }
    });
    p.on('startRenderFrame', () => {
      if (this.released || !this.wantPlay || this.state === PlayState.Idle || this.state === PlayState.Error) {
        return;
      }
      Log.i('player', `first frame line ${this.lineIndex + 1}/${this.lineCount}`);
      this.firstFrame = true;
      this.gotFrame = true;
      this.bufferStats.expose(!this.resetting, Date.now());
      this.clearStart();
    });
  }

  private logBuffer(event: string, now: number): void {
    // Diagnostics must never escape into native callbacks or source-operation recovery.
    try {
      Log.i('player', `buffer ${event} sourceEpoch=${this.sourceEpoch}` +
        ` firstFrame=${this.gotFrame} wantPlay=${this.wantPlay} resetting=${this.resetting}` +
        ` nativeState=${this.player?.state ?? 'none'} uiState=${this.state} ${this.bufferStats.cacheText(now)}`);
    } catch (_) {
    }
  }

  private interruptBuffer(reason: string): void {
    const now = Date.now();
    const pair = this.bufferStats.interrupt(now);
    this.bufferStats.expose(false, now);
    if (pair.length > 0) {
      this.logBuffer(`INTERRUPT reason=${reason} ${pair}`, now);
    }
  }

  private armBufferSummary(): void {
    this.bufferStats.observe(Date.now());
    if (this.bufferSummaryTimer >= 0) {
      return;
    }
    this.bufferSummaryTimer = setInterval(() => {
      const now = Date.now();
      this.logBuffer(`SUMMARY reason=periodic ${this.bufferStats.summary(now)}`, now);
      this.samplePlaybackInfo();
    }, BUFFER_SUMMARY_MS);
  }

  private async samplePlaybackInfo(): Promise<void> {
    const p = this.player;
    if (this.playbackInfoPending || this.released || p === null || !this.wantPlay ||
      this.resetting || !this.gotFrame) return;
    this.playbackInfoPending = true;
    const epoch = this.sourceEpoch;
    const requested = Date.now();
    try {
      const info = await p.getPlaybackInfo();
      const rate = await p.getPlaybackRate();
      if (this.released || this.player !== p || epoch !== this.sourceEpoch) return;
      const download = Number(info[media.PlaybackInfoKey.DOWNLOAD_RATE] ?? -1);
      const average = Number(info[media.PlaybackInfoKey.AVG_DOWNLOAD_RATE] ?? -1);
      const seconds = Number(info[media.PlaybackInfoKey.BUFFER_DURATION] ?? -1);
      this.logBuffer(`NATIVE sampleLagMs=${Date.now() - requested}` +
        ` reportedRate=${rate} downloadBitsPerSec=${download} averageBitsPerSec=${average}` +
        ` infoBufferRaw=${seconds} infoBufferDeclaredUnit=s`, Date.now());
    } catch (_) {
      if (!this.released && this.player === p && epoch === this.sourceEpoch) {
        this.logBuffer('NATIVE unavailable', Date.now());
      }
    } finally {
      this.playbackInfoPending = false;
    }
  }

  private finishBufferSummary(reason: string): void {
    if (this.bufferSummaryTimer >= 0) {
      clearInterval(this.bufferSummaryTimer);
      this.bufferSummaryTimer = -1;
    }
    this.interruptBuffer(reason);
    const now = Date.now();
    this.bufferStats.stop(now);
    this.logBuffer(`SUMMARY reason=${reason} ${this.bufferStats.summary(now)}`, now);
  }

  private armStall(): void {
    this.clearStall();
    if (this.state === PlayState.Paused || this.state === PlayState.Error ||
      this.state === PlayState.Idle) {
      // Nothing to rescue; arming here would only leave an inert timer behind.
      return;
    }
    const s = this.session;
    this.stallTimer = setTimeout(() => {
      if (s === this.session &&
        (this.state === PlayState.Buffering || this.state === PlayState.Playing)) {
        this.nextLine('卡顿过久');
      }
    }, STALL_SWITCH_MS);
  }

  private clearStall(): void {
    if (this.stallTimer >= 0) {
      clearTimeout(this.stallTimer);
      this.stallTimer = -1;
    }
  }

  private clearStart(): void {
    if (this.startTimer >= 0) {
      clearTimeout(this.startTimer);
      this.startTimer = -1;
    }
  }

  /** Polls the playback position; a live stream that stops advancing is stuck. */
  private armWatchdog(): void {
    this.clearWatchdog();
    this.lastPosition = -1;
    this.stalledChecks = 0;
    const s = this.session;
    this.watchdogTimer = setInterval(() => {
      if (s !== this.session || this.state !== PlayState.Playing || this.released) {
        this.clearWatchdog();
        return;
      }
      const p = this.player;
      if (p === null || p.state !== 'playing') {
        return;
      }
      const pos = p.currentTime;
      if (!Number.isFinite(pos) || pos < 0) {
        // Live timelines may be unavailable (-1), including after valid positions. Not a stall.
        this.lastPosition = -1;
        this.stalledChecks = 0;
        return;
      }
      if (this.lastPosition >= 0 && pos <= this.lastPosition) {
        this.stalledChecks++;
        if (this.stalledChecks >= WATCHDOG_STRIKES) {
          Log.w('player', `position stuck at ${Math.round(pos)}ms`);
          this.clearWatchdog();
          this.nextLine('画面卡住');
        }
      } else {
        this.stalledChecks = 0;
      }
      this.lastPosition = pos;
    }, WATCHDOG_MS);
  }

  private clearWatchdog(): void {
    if (this.watchdogTimer >= 0) {
      clearInterval(this.watchdogTimer);
      this.watchdogTimer = -1;
    }
  }

  /**
   * Starts playback of `urls[startIndex]`, falling back through the list on failure.
   * `seamless` keeps the last frame on screen (used when refreshing an expiring URL).
   */
  async open(urls: string[], headers: Record<string, string>, startIndex: number = 0,
    seamless: boolean = false, play: boolean = true): Promise<void> {
    this.urls = urls;
    this.headers = headers;
    this.lineCount = urls.length;
    this.triedInSession = 0;
    this.errorText = '';
    this.wantPlay = play;
    this.seamless = seamless && this.firstFrame;
    if (this.seamless) {
      // The surface is torn down mid-swap; surface that as a short overlay instead of a stall.
      this.reconnecting = true;
    }
    if (urls.length === 0) {
      this.interruptBuffer('empty-source');
      this.state = PlayState.Error;
      this.errorText = '没有可用的播放地址';
      return;
    }
    await this.playLine(Math.min(Math.max(0, startIndex), urls.length - 1));
  }

  get currentUrl(): string {
    return this.lineIndex < this.urls.length ? this.urls[this.lineIndex] : '';
  }

  private enqueueSource(work: () => Promise<void>): Promise<void> {
    const next = this.sourceOps.then(work, work);
    this.sourceOps = next.catch(() => {});
    return next;
  }

  private async playLine(index: number): Promise<void> {
    if (this.released) {
      return;
    }
    this.interruptBuffer('source-change');
    const s = ++this.session;
    this.lineIndex = index;
    if (!this.seamless) {
      this.state = PlayState.Loading;
      this.firstFrame = false;
    }
    this.seamless = false;
    this.gotFrame = false;
    this.clearStall();
    this.clearStart();
    await this.enqueueSource(async (): Promise<void> => {
      if (s !== this.session || this.released) {
        return;
      }
      try {
        const p = await this.ensurePlayer();
        if (s !== this.session || this.released) {
          return;
        }
        if (p.state !== 'idle') {
          this.resetting = true;
          try {
            await p.reset();
          } finally {
            this.resetting = false;
          }
        }
        if (s !== this.session || this.released) {
          return;
        }
        const src = media.createMediaSourceWithUrl(this.urls[index], this.headers);
        // HTTP-FLV live mode plays at 1.2x while its cache estimate exceeds the quick-play threshold
        // (default 5s) and returns to 1x only below 2s. The estimate divides buffered bytes by the last
        // second's read rate, so it spikes and drains the reserve that absorbs network dips. Live input
        // refills at 1x only: keep the CDN's initial burst (3600s disables catch-up) in a 19MiB ring.
        const bufferCapacity = 20;
        const quickPlayThreshold = 3600;
        const strategy: media.PlaybackStrategy = {
          preferredBufferDuration: bufferCapacity,
          thresholdForAutoQuickPlay: quickPlayThreshold,
          preferredHdr: false
        };
        this.interruptBuffer('source-assignment');
        this.sourceEpoch++;
        this.bufferStats.clearCache();
        this.armBufferSummary();
        this.logBuffer(`STRATEGY capacityHint=${bufferCapacity} startup=default quickPlay=${quickPlayThreshold}s`, Date.now());
        await p.setMediaSource(src, strategy);
        if (s !== this.session || this.released) {
          return;
        }
        this.startTimer = setTimeout(() => {
          if (s === this.session && !this.gotFrame) {
            this.nextLine('连接超时');
          }
        }, START_TIMEOUT_MS);
      } catch (e) {
        Log.w('player', `open line ${index} failed`);
        if (s === this.session && !this.released) {
          this.nextLine('打开失败');
        }
      }
    });
  }

  private nextLine(reason: string): void {
    this.interruptBuffer('recovery');
    this.clearWatchdog();
    if (!this.wantPlay) {
      // Nothing to fail over to while the user has paused; reconnect on resume instead.
      this.suspend();
      return;
    }
    this.clearStall();
    this.clearStart();
    this.triedInSession++;
    const canTry = this.autoSwitch && this.triedInSession < this.urls.length;
    if (canTry) {
      const next = (this.lineIndex + 1) % this.urls.length;
      this.notice = `${reason}，已切换到线路 ${next + 1}`;
      this.noticeSeq++;
      this.playLine(next);
      return;
    }
    if (this.onLinesExhausted !== null && this.onLinesExhausted(reason)) {
      return;
    }
    this.fail(reason);
  }

  /** Final failure reported by the owner after its own recovery attempt. */
  giveUp(msg: string): void {
    this.fail(msg);
  }

  private fail(msg: string): void {
    this.interruptBuffer('failure');
    this.session++;
    this.clearWatchdog();
    this.state = PlayState.Error;
    this.errorText = msg;
    this.wantPlay = false;
    this.reconnecting = false;
    this.clearStall();
    this.clearStart();
    const p = this.player;
    if (p !== null && p.state === 'playing') {
      // Otherwise the decoder keeps running (and audible) behind the error overlay.
      p.pause().catch(() => {
      });
    }
  }

  /** Manual line choice; resets the failover budget. */
  selectLine(index: number): void {
    if (index < 0 || index >= this.urls.length) {
      return;
    }
    this.triedInSession = 0;
    this.wantPlay = true;
    this.playLine(index);
  }

  retry(): void {
    this.selectLine(this.lineIndex);
  }

  /** True while a seamless source swap is reconnecting (the cover stays, the frame is stale). */
  @Trace reconnecting: boolean = false;

  /** Whether the user (or owner) wants the stream playing, independent of transient states. */
  get wantsPlayback(): boolean {
    return this.wantPlay;
  }

  /** AVPlayer keeps live latency small and exposes no reliable cache figure. */
  get latencyMs(): number {
    return 0;
  }

  /** Drops the connection of a paused stream without reporting an error. */
  private suspend(): void {
    this.interruptBuffer('suspend');
    this.session++;
    this.clearWatchdog();
    this.clearStall();
    this.clearStart();
    this.firstFrame = false;
    this.state = PlayState.Paused;
    this.enqueueSource(async (): Promise<void> => {
      const p = this.player;
      if (p !== null && p.state !== 'idle' && p.state !== 'released') {
        this.resetting = true;
        try {
          await p.reset();
        } finally {
          this.resetting = false;
        }
      }
    }).catch(() => {});
    this.onSuspended?.();
  }

  pause(): void {
    this.wantPlay = false;
    this.interruptBuffer('pause');
    this.clearWatchdog();
    this.clearStall();
    const p = this.player;
    if (p !== null && p.state === 'playing') {
      p.pause().catch(() => {
      });
    }
  }

  resume(): void {
    this.wantPlay = true;
    const p = this.player;
    if (p === null) {
      return;
    }
    // A paused live stream drifts behind, so reopening jumps back to the live edge. Any
    // non-playing native state (idle after suspend, error after a failed open) needs a retry.
    if (p.state !== 'playing') {
      this.retry();
    }
  }


  setVolume(v: number): void {
    this.volume = Math.max(0, Math.min(1, v));
    const p = this.player;
    if (p !== null && (p.state === 'playing' || p.state === 'paused' || p.state === 'prepared')) {
      p.setVolume(this.volume);
    }
  }

  stop(): void {
    this.finishBufferSummary('stop');
    this.session++;
    this.wantPlay = false;
    this.urls = [];
    this.headers = {};
    this.lineCount = 0;
    this.triedInSession = 0;
    this.reconnecting = false;
    this.clearWatchdog();
    this.clearStall();
    this.clearStart();
    this.state = PlayState.Idle;
    this.firstFrame = false;
    this.enqueueSource(async (): Promise<void> => {
      const p = this.player;
      if (p !== null && p.state !== 'idle' && p.state !== 'released') {
        this.resetting = true;
        try {
          await p.reset();
        } finally {
          this.resetting = false;
        }
      }
    }).catch(() => {});
  }

  release(): void {
    this.finishBufferSummary('release');
    this.released = true;
    this.session++;
    this.wantPlay = false;
    this.urls = [];
    this.headers = {};
    this.reconnecting = false;
    this.clearWatchdog();
    this.clearStall();
    this.clearStart();
    this.state = PlayState.Idle;
    this.firstFrame = false;
    const p = this.player;
    this.player = null;
    this.creating = null;
    if (p !== null) {
      p.off('stateChange');
      p.off('error');
      p.off('bufferingUpdate');
      p.off('speedDone');
      p.off('videoSizeChange');
      p.off('startRenderFrame');
      this.sourceOps.then(() => p.release()).catch(() => {});
    }
  }
}
