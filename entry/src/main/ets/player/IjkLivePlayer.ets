import { IjkMediaPlayer, InterruptEvent, InterruptHintType, OnCompletionListener, OnErrorListener,
  OnInfoListener, OnPreparedListener, OnVideoSizeChangedListener, VideoCodecMode } from '@ohos/ijkplayer';
import { Log } from '../util/Log';
import { BufferStats } from './BufferStats';
import { LivePlayerApi, PlayerEngine, PlayState } from './PlayerApi';

const START_TIMEOUT_MS = 12000;
/** Longer than AVPlayer's: the rebuffer watermark below can legitimately grow to 5 seconds. */
const STALL_SWITCH_MS = 15000;
const BUFFER_SUMMARY_MS = 30000;
/** Latency control: above START the reserve is more than any network dip needs, so play at
 * RATE (pitch kept by soundtouch, barely perceptible) until it is back to STOP. */
const CATCHUP_POLL_MS = 2000;
const CATCHUP_START_MS = 12000;
const CATCHUP_STOP_MS = 8000;
const CATCHUP_RATE = '1.05';
/** infbuf keeps downloading while paused; drop the connection before that grows unbounded. */
const PAUSED_RELEASE_MS = 30000;

// ijkplayer MEDIA_INFO codes (IMediaPlayer.java).
const INFO_VIDEO_RENDERING_START = 3;
const INFO_BUFFERING_START = 701;
const INFO_BUFFERING_END = 702;
const INFO_AUDIO_RENDERING_START = 10002;

/** Hardware decoding straight into the XComponent surface. BUFFER mode is the fallback. */
const CODEC_MODE: VideoCodecMode = VideoCodecMode.SURFACE;
/** Native FFmpeg logging: very verbose and it prints full signed URLs, so never ship it on. */
const IJK_DEBUG = false;

/** Scheme and host only: signed query strings must not reach the log. */
function urlHost(url: string): string {
  const m = url.match(/^([a-z]+:\/\/[^/?#]+)/i);
  return m === null ? 'invalid-url' : m[1];
}

/**
 * ijkplayer (FFmpeg) engine with the same contract as the AVPlayer `LivePlayer`.
 * Unlike AVPlayer's HTTP-FLV mode it never speeds up or drops data to chase latency, and each
 * rebuffer raises the amount it waits for (1.5s → 3s → up to 5s), so the reserve grows instead
 * of being spent. One native player exists per XComponent ID; every line gets a fresh one.
 */
@ObservedV2
export class IjkLivePlayer implements LivePlayerApi {
  readonly engine: PlayerEngine = PlayerEngine.Ijk;
  @Trace state: PlayState = PlayState.Idle;
  @Trace videoWidth: number = 16;
  @Trace videoHeight: number = 9;
  @Trace firstFrame: boolean = false;
  @Trace lineIndex: number = 0;
  @Trace lineCount: number = 0;
  @Trace errorText: string = '';
  @Trace volume: number = 1;
  @Trace notice: string = '';
  @Trace noticeSeq: number = 0;
  @Trace reconnecting: boolean = false;

  autoSwitch: boolean = true;
  onLinesExhausted: ((reason: string) => boolean) | null = null;
  onStreamEnded: (() => void) | null = null;
  onSuspended: (() => void) | null = null;
  onPlaying: (() => void) | null = null;

  private context: object | null = null;
  private xid: string = '';
  private native: IjkMediaPlayer | null = null;
  private urls: string[] = [];
  private headers: Record<string, string> = {};
  private session: number = 0;
  private wantPlay: boolean = true;
  private triedInSession: number = 0;
  private seamless: boolean = false;
  private gotFrame: boolean = false;
  private pendingLine: number = -1;
  /** The surface was destroyed under a running stream; the next surface must reopen it. */
  private surfaceLost: boolean = false;
  private stallTimer: number = -1;
  private startTimer: number = -1;
  private released: boolean = false;
  /** Native release and setup must not overlap on the same XComponent ID. */
  private sourceOps: Promise<void> = Promise.resolve();
  private bufferStats: BufferStats = new BufferStats();
  private bufferSummaryTimer: number = -1;
  private sourceEpoch: number = 0;
  private openedAt: number = 0;
  private catchupTimer: number = -1;
  private catchingUp: boolean = false;
  private pausedReleaseTimer: number = -1;
  /** Buffered media ahead of the picture, sampled with the catch-up poll; plain field, not traced. */
  private cachedMs: number = 0;

  get wantsPlayback(): boolean {
    return this.wantPlay;
  }

  get latencyMs(): number {
    return this.native !== null && this.gotFrame ? this.cachedMs : 0;
  }

  setSurface(_id: string): void {
  }

  bindNative(context: object, id: string): void {
    const replaced = this.surfaceLost || (this.context !== null && (this.context !== context || this.xid !== id));
    this.surfaceLost = false;
    this.context = context;
    this.xid = id;
    Log.i('player', `ijk bind xcomponent=${id} replaced=${replaced}`);
    if (this.released) {
      return;
    }
    if (this.pendingLine >= 0) {
      const line = this.pendingLine;
      this.pendingLine = -1;
      this.playLine(line);
    } else if (replaced && this.urls.length > 0 && this.wantPlay) {
      // The old surface (and the native player drawing into it) is gone; reopen at the live edge.
      this.seamless = this.firstFrame;
      this.playLine(this.lineIndex);
    }
  }

  unbindNative(id: string): void {
    if (id !== this.xid) {
      return;
    }
    Log.i('player', `ijk unbind xcomponent=${id}`);
    this.context = null;
    this.surfaceLost = this.native !== null;
    this.session++;
    this.clearStall();
    this.clearStart();
    this.interruptBuffer('surface-destroyed');
    this.enqueueRelease();
  }

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
    if (this.context === null) {
      // The XComponent has not loaded yet; bindNative() starts this line.
      this.pendingLine = index;
      return;
    }
    this.enqueueRelease();
    await this.enqueue(async (): Promise<void> => {
      if (s !== this.session || this.released || this.context === null) {
        return;
      }
      const p = new IjkMediaPlayer(this.xid);
      p.setContext(this.context, this.xid);
      p.setDebug(IJK_DEBUG);
      p.native_setup(CODEC_MODE);
      this.configure(p);
      p.setDataSource(this.urls[index]);
      // FFmpeg adds its own "User-Agent: Lavf/…" unless the user_agent option is set; a custom
      // header beside it duplicates the field, and some Bilibili CDNs answer that with 403.
      const headers = new Map<string, string>();
      Object.keys(this.headers).forEach((k: string) => {
        if (k.toLowerCase() === 'user-agent') {
          p.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'user_agent', this.headers[k]);
        } else {
          headers.set(k, this.headers[k]);
        }
      });
      if (headers.size > 0) {
        p.setDataSourceHeader(headers);
      }
      this.listen(p, s);
      p.setVolume(`${this.volume}`, `${this.volume}`);
      this.native = p;
      this.sourceEpoch++;
      this.bufferStats.clearCache();
      this.armBufferSummary();
      this.openedAt = Date.now();
      this.logBuffer(`STRATEGY engine=ijk codec=${CODEC_MODE === VideoCodecMode.SURFACE ? 'surface' : 'buffer'}` +
        ` hwm=1500/3000/5000 infbuf=1 catchup=${CATCHUP_START_MS}>${CATCHUP_RATE}x>${CATCHUP_STOP_MS}` +
        ` line=${index + 1}/${this.urls.length} source=${urlHost(this.urls[index])}`, this.openedAt);
      p.prepareAsync();
      if (this.wantPlay) {
        p.start();
      }
      this.startTimer = setTimeout(() => {
        if (s === this.session && !this.gotFrame) {
          this.nextLine('连接超时');
        }
      }, START_TIMEOUT_MS);
    });
  }

  private configure(p: IjkMediaPlayer): void {
    const PLAYER = IjkMediaPlayer.OPT_CATEGORY_PLAYER;
    const FORMAT = IjkMediaPlayer.OPT_CATEGORY_FORMAT;
    p.setOption(PLAYER, 'mediacodec-all-videos', '1');
    p.setOption(PLAYER, 'mediacodec-hevc', '1');
    p.setOption(PLAYER, 'start-on-prepared', this.wantPlay ? '1' : '0');
    // Keep reading whatever the CDN sends. This build has no latency-chasing drop option at all,
    // so the CDN's initial burst stays as the reserve and the delay can only grow.
    p.setOption(PLAYER, 'packet-buffering', '1');
    p.setOption(PLAYER, 'infbuf', '1');
    // Wait for 1.5s before the first frame and after the first stall, 3s after the next, then
    // keep doubling up to 5s (the option's maximum): repeated stalls buy a larger reserve.
    p.setOptionLong(PLAYER, 'first-high-water-mark-ms', '1500');
    p.setOptionLong(PLAYER, 'next-high-water-mark-ms', '3000');
    p.setOptionLong(PLAYER, 'last-high-water-mark-ms', '5000');
    p.setOption(PLAYER, 'framedrop', '1');
    p.setOption(PLAYER, 'soundtouch', '1');
    p.setOption(FORMAT, 'timeout', '10000000');
    p.setOption(FORMAT, 'connect_timeout', '10000000');
    p.setOption(FORMAT, 'dns_cache_timeout', '600000000');
  }

  private listen(p: IjkMediaPlayer, s: number): void {
    const prepared: OnPreparedListener = {
      onPrepared: () => {
        if (s !== this.session || this.released) {
          return;
        }
        Log.i('player', `ijk prepared afterMs=${Date.now() - this.openedAt} decoder=${p.getVideoDecoder()}`);
        if (this.wantPlay) {
          this.state = PlayState.Playing;
        } else {
          this.state = PlayState.Paused;
        }
      }
    };
    const size: OnVideoSizeChangedListener = {
      onVideoSizeChanged: (w: number, h: number, _sarNum: number, _sarDen: number) => {
        if (s === this.session && w > 0 && h > 0) {
          this.videoWidth = w;
          this.videoHeight = h;
        }
      }
    };
    const info: OnInfoListener = {
      onInfo: (what: number, extra: number) => {
        if (s !== this.session || this.released) {
          return;
        }
        this.onInfo(p, what, extra);
      }
    };
    const error: OnErrorListener = {
      onError: (what: number, extra: number) => {
        if (s !== this.session || this.released || this.state === PlayState.Idle || this.state === PlayState.Error) {
          return;
        }
        Log.w('player', `ijk error what=${what} extra=${extra} line=${this.lineIndex + 1}` +
          ` source=${urlHost(this.urls[this.lineIndex] ?? '')} afterMs=${Date.now() - this.openedAt}`);
        this.nextLine(`播放出错（${what}/${extra}）`);
      }
    };
    const completion: OnCompletionListener = {
      onCompletion: () => {
        if (s !== this.session || this.released || this.state === PlayState.Idle || this.state === PlayState.Error) {
          return;
        }
        Log.i('player', 'ijk completed');
        this.interruptBuffer('completed');
        if (!this.wantPlay) {
          this.suspend();
        } else if (this.onStreamEnded !== null) {
          this.onStreamEnded();
        } else {
          this.nextLine('直播流中断');
        }
      }
    };
    p.setOnPreparedListener(prepared);
    p.setOnVideoSizeChangedListener(size);
    p.setOnInfoListener(info);
    p.setOnErrorListener(error);
    p.setOnCompletionListener(completion);
    p.on('audioInterrupt', (e: InterruptEvent) => {
      if (s !== this.session) {
        return;
      }
      Log.i('player', `ijk audio interrupt hint=${e.hintType ?? -1}`);
      if (e.hintType === InterruptHintType.INTERRUPT_HINT_PAUSE ||
        e.hintType === InterruptHintType.INTERRUPT_HINT_STOP) {
        this.pause();
      }
    });
    p.setMessageListener();
  }

  private onInfo(p: IjkMediaPlayer, what: number, extra: number): void {
    const now = Date.now();
    switch (what) {
      case INFO_VIDEO_RENDERING_START:
        Log.i('player', `first frame line ${this.lineIndex + 1}/${this.lineCount} afterMs=${now - this.openedAt}` +
          ` decoder=${p.getVideoDecoder()}`);
        this.firstFrame = true;
        this.gotFrame = true;
        this.reconnecting = false;
        if (this.wantPlay && this.state !== PlayState.Buffering) {
          this.state = PlayState.Playing;
        }
        this.bufferStats.expose(true, now);
        this.clearStart();
        this.armCatchup(p);
        this.onPlaying?.();
        break;
      case INFO_BUFFERING_START:
        this.logBuffer(`START ${this.bufferStats.start(now)} ${this.nativeText(p)}`, now);
        this.setCatchup(p, false, 'buffering');
        if (this.wantPlay && this.state === PlayState.Playing) {
          this.state = PlayState.Buffering;
          this.armStall();
        }
        break;
      case INFO_BUFFERING_END:
        this.logBuffer(`END ${this.bufferStats.end(now)} ${this.nativeText(p)}`, now);
        if (this.state === PlayState.Buffering) {
          this.state = PlayState.Playing;
        }
        this.clearStall();
        break;
      case INFO_AUDIO_RENDERING_START:
        Log.i('player', `ijk audio start afterMs=${now - this.openedAt}`);
        break;
      default:
        Log.i('player', `ijk info what=${what} extra=${extra}`);
        break;
    }
  }

  private armCatchup(p: IjkMediaPlayer): void {
    this.clearCatchup();
    const s = this.session;
    this.catchupTimer = setInterval(() => {
      if (s !== this.session || this.native !== p || !this.wantPlay || this.state !== PlayState.Playing) {
        return;
      }
      let cached = -1;
      try {
        cached = Math.min(Number(p.getVideoCachedDuration()), Number(p.getAudioCachedDuration()));
      } catch (_) {
        return;
      }
      if (!Number.isFinite(cached) || cached < 0) {
        return;
      }
      this.cachedMs = cached;
      if (!this.catchingUp && cached > CATCHUP_START_MS) {
        this.setCatchup(p, true, `cachedMs=${cached}`);
      } else if (this.catchingUp && cached < CATCHUP_STOP_MS) {
        this.setCatchup(p, false, `cachedMs=${cached}`);
      }
    }, CATCHUP_POLL_MS);
  }

  private setCatchup(p: IjkMediaPlayer, on: boolean, why: string): void {
    if (this.catchingUp === on) {
      return;
    }
    this.catchingUp = on;
    try {
      p.setSpeed(on ? CATCHUP_RATE : '1');
    } catch (_) {
    }
    Log.i('player', `ijk catchup ${on ? 'start rate=' + CATCHUP_RATE : 'stop'} ${why}`);
  }

  private clearCatchup(): void {
    if (this.catchupTimer >= 0) {
      clearInterval(this.catchupTimer);
      this.catchupTimer = -1;
    }
    this.catchingUp = false;
    this.cachedMs = 0;
  }

  private nativeText(p: IjkMediaPlayer): string {
    // Each getter is read on its own: a missing property must not hide the others.
    const read = (name: string, get: () => number): string => {
      try {
        return `${name}=${Math.round(Number(get()) * 10) / 10}`;
      } catch (_) {
        return `${name}=na`;
      }
    };
    return [
      read('videoCachedMs', () => p.getVideoCachedDuration()),
      read('audioCachedMs', () => p.getAudioCachedDuration()),
      read('videoCachedBytes', () => p.getVideoCachedBytes()),
      read('tcpBytesPerSec', () => p.getTcpSpeed()),
      read('decodeFps', () => p.getVideoDecodeFramesPerSecond()),
      read('outputFps', () => p.getVideoOutputFramesPerSecond()),
      read('dropRate', () => p.getDropFrameRate())
    ].join(' ');
  }

  private logBuffer(event: string, now: number): void {
    try {
      Log.i('player', `buffer ${event} engine=ijk sourceEpoch=${this.sourceEpoch} firstFrame=${this.gotFrame}` +
        ` wantPlay=${this.wantPlay} uiState=${this.state}`);
    } catch (_) {
    }
    void now;
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
      const p = this.native;
      this.logBuffer(`SUMMARY reason=periodic ${this.bufferStats.summary(now)}` +
        (p !== null && this.gotFrame ? ` ${this.nativeText(p)}` : ''), now);
    }, BUFFER_SUMMARY_MS);
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

  private enqueue(work: () => Promise<void>): Promise<void> {
    const next = this.sourceOps.then(work, work);
    this.sourceOps = next.catch(() => {});
    return next;
  }

  /** Tears the current native player down before anything else touches the same XComponent ID. */
  private enqueueRelease(): void {
    this.clearCatchup();
    const p = this.native;
    this.native = null;
    if (p === null) {
      return;
    }
    this.enqueue(async (): Promise<void> => {
      try {
        p.off('audioInterrupt');
        await p.stopAsync();
        await p.releaseAsync();
      } catch (e) {
        Log.w('player', 'ijk release failed');
      }
    });
  }

  private armStall(): void {
    this.clearStall();
    const s = this.session;
    this.stallTimer = setTimeout(() => {
      if (s === this.session && this.state === PlayState.Buffering) {
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

  private nextLine(reason: string): void {
    this.interruptBuffer('recovery');
    if (!this.wantPlay) {
      this.suspend();
      return;
    }
    this.clearStall();
    this.clearStart();
    this.triedInSession++;
    if (this.autoSwitch && this.triedInSession < this.urls.length) {
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

  giveUp(msg: string): void {
    this.fail(msg);
  }

  private fail(msg: string): void {
    this.interruptBuffer('failure');
    this.clearCatchup();
    this.session++;
    this.state = PlayState.Error;
    this.errorText = msg;
    this.wantPlay = false;
    this.reconnecting = false;
    this.clearStall();
    this.clearStart();
    this.native?.pause();
  }

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

  private suspend(): void {
    this.interruptBuffer('suspend');
    this.session++;
    this.clearStall();
    this.clearStart();
    this.firstFrame = false;
    this.state = PlayState.Paused;
    this.enqueueRelease();
    this.onSuspended?.();
  }

  pause(): void {
    this.wantPlay = false;
    this.interruptBuffer('pause');
    this.clearStall();
    this.clearCatchup();
    this.native?.pause();
    if (this.state === PlayState.Playing || this.state === PlayState.Buffering) {
      this.state = PlayState.Paused;
    }
    this.clearPausedRelease();
    const s = this.session;
    this.pausedReleaseTimer = setTimeout(() => {
      this.pausedReleaseTimer = -1;
      if (s === this.session && !this.wantPlay && this.native !== null) {
        Log.i('player', 'ijk paused too long; connection released');
        this.enqueueRelease();
      }
    }, PAUSED_RELEASE_MS);
  }

  resume(): void {
    this.clearPausedRelease();
    if (this.wantPlay && this.native !== null &&
      (this.state === PlayState.Playing || this.state === PlayState.Buffering)) {
      return;
    }
    this.wantPlay = true;
    // A paused live stream drifts behind; reopening jumps back to the live edge.
    this.retry();
  }

  private clearPausedRelease(): void {
    if (this.pausedReleaseTimer >= 0) {
      clearTimeout(this.pausedReleaseTimer);
      this.pausedReleaseTimer = -1;
    }
  }

  setVolume(v: number): void {
    this.volume = Math.max(0, Math.min(1, v));
    this.native?.setVolume(`${this.volume}`, `${this.volume}`);
  }

  stop(): void {
    this.clearPausedRelease();
    this.finishBufferSummary('stop');
    this.session++;
    this.wantPlay = false;
    this.urls = [];
    this.headers = {};
    this.lineCount = 0;
    this.triedInSession = 0;
    this.pendingLine = -1;
    this.reconnecting = false;
    this.clearStall();
    this.clearStart();
    this.state = PlayState.Idle;
    this.firstFrame = false;
    this.enqueueRelease();
  }

  release(): void {
    this.clearPausedRelease();
    this.finishBufferSummary('release');
    this.released = true;
    this.session++;
    this.wantPlay = false;
    this.urls = [];
    this.headers = {};
    this.pendingLine = -1;
    this.reconnecting = false;
    this.clearStall();
    this.clearStart();
    this.state = PlayState.Idle;
    this.firstFrame = false;
    this.enqueueRelease();
  }
}
