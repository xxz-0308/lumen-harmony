import { http, socket } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Utf8 } from '../core/common/Bytes';
import { Log } from '../util/Log';
import { FlvTimestampNormalizer } from './FlvTimestampNormalizer';
import { FlvHandoff, FlvMediaHistory } from './FlvHandoff';

const MAX_REQUEST = 8192;
const MAX_SEND_QUEUE = 8 * 1024 * 1024;
// Freeze is far below the ~3s decoder cache. It covers catch-up AND the first send's acknowledgement.
const MAX_FREEZE_MS = 400;
const MAX_HELD_BYTES = 512 * 1024;
const MAX_HELD_FRAMES = 512;
// Measured GOP on 2K60 Douyu lines is 3.0-4.2s, so a compatible keyframe ahead of the old tail
// can legitimately take longer than one GOP to appear. Old output keeps flowing while waiting,
// so this window costs nothing visible unless the candidate never delivers a boundary at all.
const MAX_RENEW_MS = 8000;
// The candidate is parsed without the old stream's normalization, history and forwarding work, so
// its newest frame runs marginally ahead and every old keyframe arrives already discarded. After
// this much of the window the exact same-IDR splice has had its chance, and a forward cut to the
// candidate's own keyframe beats a full player reset and the content rewind that follows it.
const FORWARD_CUT_AFTER_MS = 2000;

class RelayTarget {
  url: string;
  headers: Record<string, string>;

  constructor(url: string, headers: Record<string, string>) {
    this.url = url;
    this.headers = headers;
  }
}

/** One AVPlayer connection owns one upstream request and one timestamp timeline. */
class RelayClient {
  private conn: socket.TCPSocketConnection;
  private lookup: (path: string) => RelayTarget | undefined;
  private onDone: (client: RelayClient) => void;
  private request: http.HttpRequest | null = null;
  private upstreamGeneration: number = 0;
  private candidate: http.HttpRequest | null = null;
  private candidateTimer: number = -1;
  private candidateResult: ((ready: boolean) => void) | null = null;
  private candidateHandoff: FlvHandoff | null = null;
  private candidateDeadline: number = 0;
  private freezeTimer: number = -1;
  private freezeStarted: number = -1;
  private boundaryOutput: number = -1;
  private heldFrames: Uint8Array[] = [];
  private heldRaw: number[] = [];
  private heldBytes: number = 0;
  private retiringRequest: http.HttpRequest | null = null;
  private activeHandoff: FlvHandoff | null = null;
  private path: string = '';
  private videoCodec: number = 0;
  private audioCodec: number = 0;
  private videoHeader: Uint8Array | null = null;
  private audioHeader: Uint8Array | null = null;
  private lastTimestamp: number = 0;
  private transform: FlvTimestampNormalizer = new FlvTimestampNormalizer();
  private mediaHistory: FlvMediaHistory = new FlvMediaHistory();
  private timelineReportedAt: number = Date.now();
  private incoming: Uint8Array = new Uint8Array(0);
  private writes: Promise<void> = Promise.resolve();
  private queuedBytes: number = 0;
  private windowInBytes: number = 0;
  private windowOutBytes: number = 0;
  private windowStartTs: number = -1;
  private windowVideoFrames: number = 0;
  private windowAudioFrames: number = 0;
  private inboundGaps: number = 0;
  private lastInboundAt: number = -1;
  private activeUrl: string = '';
  private candidateSameSignature: boolean = false;
  private candidateOpenedAt: number = -1;
  private candidateInBytes: number = 0;
  private candidateWindowIdrs: number = 0;
  private lastSendAt: number = -1;
  private sendGaps: number = 0;
  private timeout: number = -1;
  private requested: boolean = false;
  private started: boolean = false;
  private upstreamEnded: boolean = false;
  private lastUpstreamDataAt: number = -1;
  private closed: boolean = false;

  constructor(conn: socket.TCPSocketConnection, lookup: (path: string) => RelayTarget | undefined,
    onDone: (client: RelayClient) => void) {
    this.conn = conn;
    this.lookup = lookup;
    this.onDone = onDone;
    conn.on('message', (info: socket.SocketMessageInfo) => this.receiveRequest(new Uint8Array(info.message)));
    conn.on('close', () => this.close());
    conn.on('error', () => this.close());
    this.armTimeout(8000);
  }

  private armTimeout(ms: number): void {
    if (this.timeout >= 0) {
      clearTimeout(this.timeout);
    }
    this.timeout = setTimeout(() => this.close(), ms);
  }

  private receiveRequest(bytes: Uint8Array): void {
    if (this.closed || this.requested) {
      return;
    }
    if (bytes.length + this.incoming.length > MAX_REQUEST) {
      this.reject(431);
      return;
    }
    const data = new Uint8Array(this.incoming.length + bytes.length);
    data.set(this.incoming);
    data.set(bytes, this.incoming.length);
    this.incoming = data;
    let text: string;
    try {
      text = Utf8.decode(data);
    } catch (e) {
      this.reject(400);
      return;
    }
    const end = text.indexOf('\r\n\r\n');
    if (end < 0) {
      return;
    }
    this.requested = true;
    this.incoming = new Uint8Array(0);
    const lines = text.substring(0, end).split('\r\n');
    const match = lines[0].match(/^(GET|HEAD) (\/[0-9a-f]{32}\.flv) HTTP\/1\.[01]$/);
    if (match === null) {
      this.reject(400);
      return;
    }
    this.path = match[2];
    const target = this.lookup(this.path);
    if (target === undefined) {
      this.reject(404);
      return;
    }
    for (const line of lines.slice(1)) {
      // A live stream has no byte offsets. Ranges from 0 (bounded probes included) get the whole
      // stream with 200, which HTTP permits; anything else cannot be honoured.
      if (line.toLowerCase().startsWith('range:') && !/^range:\s*bytes=0-\d*\s*$/i.test(line)) {
        this.reject(416);
        return;
      }
    }
    if (match[1] === 'HEAD') {
      this.write(Utf8.encode('HTTP/1.1 200 OK\r\nContent-Type: video/x-flv\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'));
      this.writes.then(() => this.close());
      return;
    }
    this.armTimeout(20000);
    this.activeUrl = target.url;
    const req = http.createHttp();
    this.request = req;
    const generation = ++this.upstreamGeneration;
    req.on('dataReceive', (part: ArrayBuffer) => {
      if (this.request === req && generation === this.upstreamGeneration) {
        this.receiveStream(part);
      }
    });
    req.on('dataEnd', () => this.endStream(req));
    try {
      // Streaming receive events arrive before requestInStream completes on live connections.
      req.requestInStream(target.url, {
        method: http.RequestMethod.GET,
        header: target.headers,
        usingCache: false,
        connectTimeout: 12000,
        readTimeout: 0
      }).then((status: number) => {
        if (this.request === req && generation === this.upstreamGeneration &&
          (status < 200 || status >= 300)) {
          this.fail();
        }
      }).catch(() => {
        if (this.request === req && generation === this.upstreamGeneration) {
          this.fail();
        }
      });
    } catch (e) {
      this.fail();
    }
  }

  private receiveStream(part: ArrayBuffer): void {
    if (this.closed) {
      return;
    }
    this.armTimeout(20000);
    const inboundAt = Date.now();
    if (this.lastInboundAt >= 0 && inboundAt - this.lastInboundAt > 500) {
      this.inboundGaps++;
    }
    this.lastInboundAt = inboundAt;
    this.windowInBytes += part.byteLength;
    try {
      const parser = this.activeHandoff ?? this.transform;
      const frames = parser.push(new Uint8Array(part));
      for (const frame of frames) {
        if (frame.length >= 17 && ((frame[0] === 9 && frame[12] === 1) ||
          (frame[0] === 8 && ((frame[11] >>> 4) !== 10 || frame[12] === 1)))) {
          this.lastUpstreamDataAt = Date.now(); // A metadata/partial-tag trickle is not healthy media.
          break;
        }
      }
      if (frames.length > 0 && !this.started) {
        this.started = true;
        this.write(Utf8.encode('HTTP/1.1 200 OK\r\nContent-Type: video/x-flv\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'));
      }
      this.admitFrames(frames, parser.rawTimestamps);
    } catch (e) {
      Log.w('relay', 'invalid upstream FLV data');
      this.fail();
    }
  }

  private admitFrames(frames: Uint8Array[], raw: number[]): void {
    this.checkCandidateDeadline();
    let start = 0;
    for (let i = 0; i < frames.length && !this.closed; i++) {
      const candidate = this.candidate;
      const handoff = this.candidateHandoff;
      if (candidate === null || handoff === null || this.retiringRequest !== null) {
        break;
      }
      if (this.freezeStarted < 0 && FlvHandoff.isIdr(frames[i], this.videoHeader)) {
        this.candidateWindowIdrs++;
        this.forwardFrames(frames.slice(start, i), raw.slice(start, i));
        start = i;
        if (this.closed) {
          return;
        }
        try {
          if (handoff.holdBoundary(frames[i], raw[i], this.lastTimestamp)) {
            this.freezeStarted = Date.now();
            this.boundaryOutput = RelayClient.timestamp(frames[i]);
            this.freezeTimer = setTimeout(() => this.abandonCandidate(candidate, 'freeze-timeout'), MAX_FREEZE_MS);
          }
        } catch (_) {
          this.abandonCandidate(candidate, handoff.pendingReason);
          break;
        }
      }
      if (this.freezeStarted >= 0) {
        if (this.heldBytes + frames[i].length > MAX_HELD_BYTES ||
          this.heldFrames.length >= MAX_HELD_FRAMES ||
          ((RelayClient.timestamp(frames[i]) - this.boundaryOutput) | 0) >= MAX_FREEZE_MS ||
          Date.now() - this.freezeStarted >= MAX_FREEZE_MS) {
          this.abandonCandidate(candidate, 'freeze-limit');
          // Earlier held frames were replayed. The over-limit frame and remainder still follow.
          start = i;
          break;
        }
        this.heldFrames.push(frames[i]);
        this.heldRaw.push(raw[i]);
        this.heldBytes += frames[i].length;
        start = i + 1;
      }
    }
    this.forwardFrames(frames.slice(start), raw.slice(start));
  }

  private static timestamp(frame: Uint8Array): number {
    return (frame[4] * 65536 + frame[5] * 256 + frame[6] + frame[7] * 16777216) >>> 0;
  }

  private checkCandidateDeadline(): void {
    if (this.candidate !== null && (Date.now() >= this.candidateDeadline ||
      (this.freezeStarted >= 0 && Date.now() - this.freezeStarted >= MAX_FREEZE_MS))) {
      this.abandonCandidate(this.candidate, 'deadline');
    }
  }

  private endStream(req: http.HttpRequest): void {
    if (this.request !== req || this.closed) {
      return;
    }
    this.upstreamEnded = true;
    if (this.candidate !== null) {
      this.abandonCandidate(this.candidate, 'old-ended');
    }
    if (!this.started) {
      this.fail();
      return;
    }
    // Rollback was enqueued before taking this drain snapshot, including a held final IDR.
    this.writes.then(() => {
      if (this.request === req) {
        this.close();
      }
    });
  }

  private forwardFrames(frames: Uint8Array[], raw: number[]): void {
    let total = 0;
    for (const frame of frames) {
      total += frame.length;
    }
    if (total === 0 || this.closed) {
      return;
    }
    const payload = new Uint8Array(total);
    let offset = 0;
    for (const frame of frames) {
      payload.set(frame, offset);
      offset += frame.length;
    }
    if (!this.write(payload)) {
      return;
    }
    this.windowOutBytes += total;
    // Queue admission is the single authority for both decoder tail and content history.
    // Never update either from parser callbacks or while the old boundary is withheld.
    for (let i = 0; i < frames.length; i++) {
      const frame = frames[i];
      if (raw[i] >= 0) {
        this.mediaHistory.observe(frame, raw[i]);
      }
      if (frame.length >= 15 && (frame[0] === 8 || frame[0] === 9)) {
        if (frame[0] === 8) {
          this.windowAudioFrames++;
          this.audioCodec = frame[11] >>> 4;
          if (this.audioCodec === 10 && frame[12] === 0) {
            this.audioHeader = frame;
          }
        } else {
          this.windowVideoFrames++;
          this.videoCodec = frame[11] & 15;
          if (this.videoCodec === 7 && frame[12] === 0) {
            this.videoHeader = frame;
          }
        }
        this.lastTimestamp = RelayClient.timestamp(frame);
      }
    }
    const now = Date.now();
    if (now - this.timelineReportedAt >= 30000) {
      const elapsedSec = (now - this.timelineReportedAt) / 1000;
      const inMbps = (this.windowInBytes * 8 / elapsedSec / 1e6).toFixed(2);
      const outMbps = (this.windowOutBytes * 8 / elapsedSec / 1e6).toFixed(2);
      const gaps = this.inboundGaps;
      const rxVideo = this.windowVideoFrames;
      const rxAudio = this.windowAudioFrames;
      // Timeline advance is the only honest measure of whether the pipe keeps real time;
      // byte rates cannot distinguish variable bitrate content from a starving connection.
      const baseTs = this.windowStartTs < 0 ? this.lastTimestamp : this.windowStartTs;
      const advMs = this.lastTimestamp - baseTs;
      const realtime = advMs / (elapsedSec * 1000);
      this.windowInBytes = 0;
      this.windowOutBytes = 0;
      this.inboundGaps = 0;
      this.windowVideoFrames = 0;
      this.windowAudioFrames = 0;
      this.windowStartTs = this.lastTimestamp;
      this.timelineReportedAt = now;
      try {
        Log.i('relay', `timeline window ${this.mediaHistory.summary()} queuedBytes=${this.queuedBytes} ` +
          `inMbps=${inMbps} outMbps=${outMbps} upstreamGaps=${gaps} rxVideo=${rxVideo} rxAudio=${rxAudio} ` +
          `timelineAdvanceMs=${advMs} wallMs=${Math.round(elapsedSec * 1000)} realtime=${realtime.toFixed(3)} ` +
          `sendGaps=${this.sendGaps}`);
      } catch (_) {
      }
    }
  }

  get targetPath(): string {
    return this.path;
  }

  get streaming(): boolean {
    return this.started && !this.closed;
  }

  get healthy(): boolean {
    return this.streaming && !this.upstreamEnded && this.request !== null &&
      this.lastUpstreamDataAt >= 0 && Date.now() - this.lastUpstreamDataAt < 1000;
  }

  /** Preconnect a renewed signature and hand off at a compatible video keyframe. */
  renew(target: RelayTarget): Promise<boolean> {
    if (this.closed || this.upstreamEnded || !this.requested || !this.started || this.videoCodec !== 7 || this.retiringRequest !== null) {
      return Promise.resolve(false);
    }
    if (this.candidate !== null) {
      this.abandonCandidate(this.candidate);
    }
    if (this.closed) {
      return Promise.resolve(false); // A superseded attempt's rollback may fail queue admission.
    }
    return new Promise<boolean>((resolve: (ready: boolean) => void) => {
      const req = http.createHttp();
      const renewTail = this.lastTimestamp;
      const renewStarted = Date.now();
      const handoff = new FlvHandoff(this.videoCodec, this.audioCodec, renewTail,
        this.videoHeader, this.audioHeader, this.mediaHistory);
      this.candidate = req;
      this.candidateHandoff = handoff;
      this.candidateDeadline = renewStarted + MAX_RENEW_MS;
      this.candidateSameSignature = this.activeUrl.length > 0 && this.activeUrl === target.url;
      this.candidateWindowIdrs = 0;
      this.candidateOpenedAt = renewStarted;
      this.candidateInBytes = 0;
      this.candidateResult = resolve;
      this.candidateTimer = setTimeout(() =>
        this.abandonCandidate(req, `timeout-${handoff.pendingReason}`), MAX_RENEW_MS);
      req.on('dataReceive', (part: ArrayBuffer) => {
        this.checkCandidateDeadline();
        if (this.closed) {
          return;
        }
        if (this.request === req) {
          this.receiveStream(part);
          return;
        }
        if (this.candidate !== req) {
          return;
        }
        try {
          this.candidateInBytes += part.byteLength;
          const frames = handoff.push(new Uint8Array(part), this.lastTimestamp,
            Date.now() - renewStarted >= FORWARD_CUT_AFTER_MS);
          this.checkCandidateDeadline();
          if (handoff.ready && this.candidate === req) {
            const switchTail = this.lastTimestamp;
            const heldBytes = this.heldBytes;
            // Irreversible once candidate bytes enter the TCP queue. Before this point every
            // failure replays the held old bytes; after it a failed/blocked send closes output.
            this.retiringRequest = this.request;
            this.request = req;
            this.upstreamEnded = false;
            this.lastUpstreamDataAt = Date.now();
            this.upstreamGeneration++;
            this.activeHandoff = handoff;
            this.heldFrames = [];
            this.heldRaw = [];
            this.heldBytes = 0;
            this.armTimeout(20000);
            this.forwardFrames(frames, handoff.rawTimestamps);
            const admitted = this.writes;
            admitted.then(() => {
              this.checkCandidateDeadline();
              if (this.closed || this.candidate !== req) {
                return;
              }
              this.retiringRequest?.destroy();
              this.retiringRequest = null;
              this.candidate = null;
              const freezeStats = this.freezeSummary(heldBytes, handoff.cutForward);
              this.finishCandidate(true);
              // Send acknowledgement is not evidence of AVPlayer decoding: keep that distinction.
              Log.i('relay', `renewed FLV upstream without resetting player proof=media-sequence ` +
                `mode=${handoff.cutForward ? 'forward-cut' : 'same-idr'} ` +
                `matched=${handoff.matchedPackets} skippedOverlap=${handoff.skippedOverlap} ` +
                `skippedMedia=${handoff.skippedMedia} skippedKeys=${handoff.skippedKeyframes} ` +
                `contentAdvanceMs=${handoff.contentAdvanceMs} oldAdvanceMs=${switchTail - renewTail} ` +
                `${freezeStats} firstOutput=${handoff.firstOutputTimestamp} waitMs=${Date.now() - renewStarted}`);
            });
          }
        } catch (e) {
          this.abandonCandidate(req, handoff.pendingReason);
        }
      });
      req.on('dataEnd', () => {
        if (this.candidate === req) {
          this.abandonCandidate(req, `ended-${handoff.pendingReason}`);
        } else {
          this.endStream(req);
        }
      });
      try {
        req.requestInStream(target.url, {
          method: http.RequestMethod.GET,
          header: target.headers,
          usingCache: false,
          connectTimeout: 12000,
          readTimeout: 0
        }).then((status: number) => {
          if (status < 200 || status >= 300) {
            if (this.candidate === req) {
              this.abandonCandidate(req);
            } else if (this.request === req) {
              this.fail();
            }
          }
        }).catch(() => {
          if (this.candidate === req) {
            this.abandonCandidate(req);
          } else if (this.request === req) {
            this.fail();
          }
        });
      } catch (e) {
        this.abandonCandidate(req);
      }
    });
  }

  private finishCandidate(ready: boolean): void {
    if (this.candidateTimer >= 0) {
      clearTimeout(this.candidateTimer);
      this.candidateTimer = -1;
    }
    if (this.freezeTimer >= 0) {
      clearTimeout(this.freezeTimer);
      this.freezeTimer = -1;
    }
    this.candidateHandoff = null;
    this.freezeStarted = -1;
    this.boundaryOutput = -1;
    const result = this.candidateResult;
    this.candidateResult = null;
    result?.(ready);
  }

  private freezeSummary(heldBytes: number = this.heldBytes, cut: boolean = false): string {
    return `freezeWait=${this.freezeStarted < 0 ? 0 : Date.now() - this.freezeStarted} ` +
      `heldBytes=${heldBytes} boundary=${this.boundaryOutput < 0 ? 'none' : (cut ? 'forward-cut' : 'same-idr')} ` +
      `boundaryOutput=${this.boundaryOutput}`;
  }

  private abandonCandidate(req: http.HttpRequest, reason: string = 'preconnect-failed'): void {
    if (this.candidate !== req) {
      return;
    }
    const committing = this.retiringRequest !== null;
    const candidateMs = this.candidateOpenedAt < 0 ? 0 : Date.now() - this.candidateOpenedAt;
    const diagnostics = this.freezeSummary() +
      ` sameSignature=${this.candidateSameSignature} candidateMs=${candidateMs} candidateBytes=${this.candidateInBytes}` +
      ` oldIdrsInWindow=${this.candidateWindowIdrs} ${this.candidateHandoff?.boundaryDiagnostics() ?? 'bd none'}`;
    const matched = this.candidateHandoff?.matchedPackets ?? 0;
    const frames = this.heldFrames;
    const raw = this.heldRaw;
    this.heldFrames = [];
    this.heldRaw = [];
    this.heldBytes = 0;
    this.candidate = null;
    req.destroy();
    this.finishCandidate(false);
    if (committing) {
      // Candidate bytes may already have reached the demuxer. Replaying old here would duplicate
      // them; send failure/timeout is an explicit closed output, never a false seamless success.
      Log.w('relay', `renewal fallback reason=${reason} phase=output-commit matched=${matched} ${diagnostics}; closing output, no seamless claim`);
      this.close();
    } else {
      this.forwardFrames(frames, raw);
      Log.w('relay', `renewal fallback reason=${reason} matched=${matched} ${diagnostics}; ` +
        `${this.closed ? 'output closed' : 'replayed held old data, keeping current stream'}, no seamless claim`);
    }
  }

  private write(bytes: Uint8Array): boolean {
    if (this.closed) {
      return false;
    }
    if (this.queuedBytes + bytes.length > MAX_SEND_QUEUE) {
      Log.w('relay', 'player fell behind live stream');
      this.close();
      return false;
    }
    this.queuedBytes += bytes.length;
    const payload = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    this.writes = this.writes.then(async () => {
      try {
        if (!this.closed) {
          await this.conn.send({ data: payload });
          const sentAt = Date.now();
          if (this.lastSendAt >= 0 && sentAt - this.lastSendAt > 200) {
            this.sendGaps++;
            if (this.sendGaps <= 6) {
              Log.i('relay', `local send gap ${sentAt - this.lastSendAt}ms bytes=${bytes.length} queuedBytes=${this.queuedBytes}`);
            }
          }
          this.lastSendAt = sentAt;
        }
      } finally {
        this.queuedBytes -= bytes.length;
      }
    }).catch(() => this.close());
    return true;
  }

  private reject(status: number): void {
    this.write(Utf8.encode(`HTTP/1.1 ${status} Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`));
    this.writes.then(() => this.close());
  }

  private fail(): void {
    if (this.closed) {
      return;
    }
    if (this.started) {
      this.close();
    } else {
      this.reject(502);
    }
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.upstreamGeneration++;
    if (this.timeout >= 0) {
      clearTimeout(this.timeout);
      this.timeout = -1;
    }
    if (this.candidate !== null) {
      this.abandonCandidate(this.candidate, 'output-closed');
    }
    this.retiringRequest?.destroy();
    this.retiringRequest = null;
    this.request?.destroy();
    this.request = null;
    this.conn.close().catch(() => {
    });
    this.onDone(this);
  }
}

/** Loopback-only streaming relay. Signed upstream addresses never appear in local playback URLs. */
export class DouyuStreamRelay {
  private server: socket.TCPSocketServer | null = null;
  private starting: Promise<void> | null = null;
  private port: number = 0;
  private generation: number = 0;
  private closed: boolean = false;
  private targets: Map<string, RelayTarget> = new Map<string, RelayTarget>();
  private targetPaths: string[] = [];
  private clients: Set<RelayClient> = new Set<RelayClient>();
  private staleClients: Set<RelayClient> = new Set<RelayClient>();
  private staleTimers: Set<number> = new Set<number>();

  private async start(): Promise<void> {
    if (this.server !== null) {
      return;
    }
    if (this.starting !== null) {
      await this.starting;
      return;
    }
    const server = socket.constructTCPSocketServerInstance();
    this.starting = (async () => {
      let port = 0;
      try {
        await server.listen({ address: '127.0.0.1', family: 1, port: 0 });
        port = (await server.getLocalAddress()).port ?? 0;
      } catch (e) {
        port = 0;
      }
      if (this.closed || !port) {
        // Never leave a bound listener behind when startup is abandoned half way.
        await server.close().catch(() => {
        });
        throw new Error('Cannot start local live relay');
      }
      this.port = port;
      this.server = server;
      server.on('connect', (conn: socket.TCPSocketConnection) => {
        if (this.closed) {
          conn.close().catch(() => {
          });
          return;
        }
        if (this.clients.size >= 4) {
          // Evict the oldest instead of refusing; a stale socket must not block a new one.
          const oldest = this.clients.values().next();
          if (!oldest.done) {
            oldest.value.close();
          }
        }
        const client = new RelayClient(conn, (path: string) => this.targets.get(path),
          (done: RelayClient) => {
            this.clients.delete(done);
            this.staleClients.delete(done);
          });
        this.clients.add(client);
      });
      server.on('error', () => Log.w('relay', 'loopback listener error'));
    })();
    try {
      await this.starting;
    } finally {
      this.starting = null;
    }
  }

  async register(urls: string[], headers: Record<string, string>): Promise<string[]> {
    if (this.closed) {
      throw new Error('Local live relay is closed');
    }
    const generation = ++this.generation;
    // The player is still reading the previous source while we resolve replacements.
    // Closing those sockets here makes it see a body EOF and report a stream end,
    // so let them drain a few seconds; dispose() still closes everything immediately.
    const stale = Array.from(this.clients);
    this.clients.clear();
    for (const client of stale) {
      this.staleClients.add(client);
    }
    if (stale.length > 0) {
      const timer = setTimeout(() => {
        this.staleTimers.delete(timer);
        stale.forEach((client: RelayClient) => client.close());
      }, 4000);
      this.staleTimers.add(timer);
    }
    this.targets.clear();
    this.targetPaths = [];
    await this.start();
    if (this.closed || generation !== this.generation) {
      return [];
    }
    const result: string[] = [];
    for (const url of urls) {
      const bytes = (await cryptoFramework.createRandom().generateRandom(16)).data;
      if (this.closed || generation !== this.generation) {
        return [];
      }
      let token = '';
      for (const b of bytes) {
        token += b.toString(16).padStart(2, '0');
      }
      const path = `/${token}.flv`;
      this.targets.set(path, new RelayTarget(url, headers));
      this.targetPaths.push(path);
      result.push(`http://127.0.0.1:${this.port}${path}`);
    }
    return result;
  }

  /** A false renewal result can retain usable old output, but is NEVER reported as a handoff. */
  get canKeepCurrentStream(): boolean {
    if (this.closed) {
      return false;
    }
    let active = 0;
    for (const client of this.clients) {
      if (client.streaming) {
        if (!client.healthy) {
          return false;
        }
        active++;
      }
    }
    return active > 0;
  }

  /** Replace signed upstream targets without changing the local playback address or AVPlayer. */
  async renew(urls: string[], headers: Record<string, string>): Promise<boolean> {
    if (this.closed || urls.length === 0 || this.targetPaths.length === 0) {
      throw new Error('Cannot renew live stream');
    }
    const generation = this.generation;
    const replacements = new Map<string, RelayTarget>();
    for (let i = 0; i < this.targetPaths.length; i++) {
      const path = this.targetPaths[i];
      replacements.set(path, new RelayTarget(urls[i % urls.length], headers));
    }
    const pending: Promise<boolean>[] = [];
    for (const client of this.clients) {
      const target = replacements.get(client.targetPath);
      if (target !== undefined && client.streaming) {
        pending.push(client.renew(target));
      }
    }
    if (pending.length === 0) {
      return false;
    }
    const results = await Promise.all(pending);
    // A metadata/probe client is harmless, but one active player socket left on the expired
    // source would still fail. Treat a partial handoff as a fallback, never as success.
    const handedOff = results.every((ok: boolean) => ok);
    if (handedOff && !this.closed && generation === this.generation) {
      replacements.forEach((target: RelayTarget, path: string) => {
        this.targets.set(path, target);
      });
    }
    return handedOff && !this.closed && generation === this.generation;
  }

  dispose(): void {
    this.closed = true;
    this.generation++;
    this.targets.clear();
    this.targetPaths = [];
    this.staleTimers.forEach((timer: number) => clearTimeout(timer));
    this.staleTimers.clear();
    this.clients.forEach((client: RelayClient) => client.close());
    this.staleClients.forEach((client: RelayClient) => client.close());
    this.clients.clear();
    this.staleClients.clear();
    const server = this.server;
    this.server = null;
    if (server !== null) {
      server.close().catch(() => {
      });
    }
  }
}
