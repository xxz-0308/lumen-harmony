import { FlvTimestampNormalizer } from './FlvTimestampNormalizer';

const HISTORY_LIMIT = 512; // Per track; at most 1024 small descriptors, never media payloads.
const HISTORY_MS = 8000;
const PROOF_PACKETS = 6;
// Measured on live Douyu 原画2K60 lines: keyframes p50=306KB, max=403KB, while inter frames stay
// under 168KB. A 256KB ceiling therefore rejected EVERY keyframe on those rooms, so no boundary
// could ever be proven and every signed-URL renewal fell back to a full player reset (the visible
// ~2s rewind). The ceiling only guards against pathological packets, so it sits well above I-frames.
const MAX_FINGERPRINT_BYTES = 4 * 1024 * 1024;
// A compatible boundary must be strictly ahead of the old tail (never a rewind). The held frame
// is the old stream's own keyframe, forwarded right up to that point, so this distance is one
// frame interval in practice and the ceiling only rejects a boundary spanning a real gap.
const MAX_HANDOFF_ADVANCE = 2000;

function timestamp(tag: Uint8Array): number {
  return (tag[4] * 65536 + tag[5] * 256 + tag[6] + tag[7] * 16777216) >>> 0;
}

function setTimestamp(tag: Uint8Array, value: number): Uint8Array {
  const copy = tag.slice();
  copy[4] = (value >>> 16) & 255;
  copy[5] = (value >>> 8) & 255;
  copy[6] = value & 255;
  copy[7] = (value >>> 24) & 255;
  return copy;
}

function media(tag: Uint8Array): boolean {
  return (tag[0] === 9 && tag.length > 20 && (tag[11] & 15) === 7 && tag[12] === 1) ||
    (tag[0] === 8 && tag.length > 17 && ((tag[11] >>> 4) !== 10 || tag[12] === 1));
}

function presentation(tag: Uint8Array, raw: number): number {
  if (tag[0] !== 9) {
    return raw;
  }
  const cts = ((tag[13] * 65536 + tag[14] * 256 + tag[15]) << 8) >> 8;
  return (raw + cts) >>> 0;
}

function fingerprint(tag: Uint8Array): string {
  // Hash every payload byte (including AVC composition time), not a thumbnail/static keyframe
  // or a sampled prefix. Oversized packets cannot establish a proof. Two independent 32-bit
  // hashes are for accidental identity, not an adversarial/cryptographic content guarantee.
  if (tag.length - 15 > MAX_FINGERPRINT_BYTES) {
    return '';
  }
  let a = 2166136261;
  let b = 5381;
  for (let i = 11; i < tag.length - 4; i++) {
    a = Math.imul(a ^ tag[i], 16777619);
    b = (Math.imul(b, 33) ^ tag[i]) | 0;
  }
  return `${tag[0]}:${tag.length}:${a >>> 0}:${b >>> 0}`;
}

class MediaSample {
  raw: number;
  key: string;
  output: number;

  constructor(raw: number, key: string, output: number = -1) {
    this.raw = raw;
    this.key = key;
    this.output = output;
  }
}

/** Recent packets actually admitted to the local player's ordered output queue. */
export class FlvMediaHistory {
  video: MediaSample[] = [];
  audio: MediaSample[] = [];
  epoch: number = 0;
  tailRaw: number = -1;
  tailPresentation: number = -1;
  tailOutputPresentation: number = -1;
  private videoConfig: string = '';
  private audioConfig: string = '';

  observe(tag: Uint8Array, raw: number): void {
    if (tag.length < 17) {
      return;
    }
    const video = tag[0] === 9;
    if ((video && tag[12] === 0) ||
      (tag[0] === 8 && (tag[11] >>> 4) === 10 && tag[12] === 0)) {
      const config = fingerprint(tag);
      const previous = video ? this.videoConfig : this.audioConfig;
      if (previous !== '' && previous !== config) {
        this.reset();
      }
      if (video) {
        this.videoConfig = config;
      } else {
        this.audioConfig = config;
      }
      return;
    }
    if (!media(tag)) {
      return;
    }
    let track = video ? this.video : this.audio;
    if (track.length > 0) {
      const delta = (raw - track[track.length - 1].raw) | 0;
      if (delta < 0 || delta > HISTORY_MS) {
        this.reset(); // Never carry a content proof across a reset concealed by normalization.
        track = video ? this.video : this.audio;
      }
    }
    track.push(new MediaSample(raw, fingerprint(tag), timestamp(tag)));
    while (track.length > HISTORY_LIMIT || ((raw - track[0].raw) | 0) > HISTORY_MS) {
      track.shift();
    }
    if (this.tailRaw < 0 || ((raw - this.tailRaw) | 0) > 0) {
      this.tailRaw = raw;
    }
    const pts = presentation(tag, raw);
    if (this.tailPresentation < 0 || ((pts - this.tailPresentation) | 0) > 0) {
      this.tailPresentation = pts;
    }
    const outputPts = presentation(tag, timestamp(tag));
    if (this.tailOutputPresentation < 0 || ((outputPts - this.tailOutputPresentation) | 0) > 0) {
      this.tailOutputPresentation = outputPts;
    }
  }

  summary(): string {
    return `${this.trackSummary('video', this.video)} ${this.trackSummary('audio', this.audio)} epoch=${this.epoch}`;
  }

  private trackSummary(name: string, samples: MediaSample[]): string {
    const count = samples.length;
    const rawSpan = count > 1 ? (samples[count - 1].raw - samples[0].raw) | 0 : 0;
    const outputSpan = count > 1 ? (samples[count - 1].output - samples[0].output) | 0 : 0;
    let timingDistortions = 0;
    let maxStepErrorMs = 0;
    for (let i = 1; i < count; i++) {
      const rawStep = (samples[i].raw - samples[i - 1].raw) | 0;
      const outputStep = (samples[i].output - samples[i - 1].output) | 0;
      const error = Math.abs(outputStep - rawStep);
      if (error > 1) {
        timingDistortions++;
      }
      maxStepErrorMs = Math.max(maxStepErrorMs, error);
    }
    return `${name}Frames=${count} ${name}RawMs=${rawSpan} ${name}OutputMs=${outputSpan} ` +
      `${name}TimingDistortions=${timingDistortions} ${name}MaxStepErrorMs=${maxStepErrorMs}`;
  }

  private reset(): void {
    this.video = [];
    this.audio = [];
    this.tailRaw = -1;
    this.tailPresentation = -1;
    this.tailOutputPresentation = -1;
    this.epoch++;
  }

  /** Unique, ordered same-track sequences must also have exactly the same raw time deltas. */
  static offsets(candidate: MediaSample[], old: MediaSample[]): number[] {
    if (candidate.length !== PROOF_PACKETS ||
      ((candidate[PROOF_PACKETS - 1].raw - candidate[0].raw) | 0) < 60) {
      return [];
    }
    const unique = new Set<string>();
    for (const sample of candidate) {
      if (sample.key === '' || unique.has(sample.key)) {
        return []; // Repeated static/silent packets are not distinct evidence.
      }
      unique.add(sample.key);
    }
    const result: number[] = [];
    for (let i = 0; i <= old.length - PROOF_PACKETS; i++) {
      const offset = (old[i].raw - candidate[0].raw) | 0;
      let matches = true;
      for (let j = 0; j < PROOF_PACKETS; j++) {
        if (old[i + j].key !== candidate[j].key ||
          ((old[i + j].raw - candidate[j].raw) | 0) !== offset) {
          matches = false;
          break;
        }
      }
      if (matches && !result.includes(offset)) {
        result.push(offset);
      }
    }
    return result;
  }
}

/** Prove a common encoding timeline, then replace exactly the withheld old IDR, never a later GOP. */
export class FlvHandoff {
  private parser: FlvTimestampNormalizer = new FlvTimestampNormalizer();
  private outputClock: FlvTimestampNormalizer = new FlvTimestampNormalizer();
  private videoHeader: Uint8Array | null = null;
  private audioHeader: Uint8Array | null = null;
  private videoWindow: MediaSample[] = [];
  private audioWindow: MediaSample[] = [];
  private lastVideoRaw: number = -1;
  private lastAudioRaw: number = -1;
  private offset: number | null = null;
  private boundaryRaw: number = -1;
  private boundaryKey: string = '';
  private boundaryOutput: number = -1;
  private oldAudioRaw: number = -1;
  private oldPresentation: number = 0;
  private oldOutputPresentation: number = 0;
  private initialVideoHeader: Uint8Array | null;
  private initialAudioHeader: Uint8Array | null;
  private expectedVideo: number;
  private expectedAudio: number;
  private history: FlvMediaHistory;
  private epoch: number;
  ready: boolean = false;
  pendingReason: string = 'unproven-overlap';
  /** A live CDN can hand two connections of one session different encoder configs (measured on a
   * 2K60 Douyu line: a 49-byte and a 50-byte video config, identical audio), while the coded frames
   * stay byte-identical and the already-playing connection keeps decoding under the config it was
   * given at connect. A substantive change would have broken that playing connection, so identity
   * rests on the packet proof plus a byte-identical boundary IDR, and the candidate's own config is
   * replayed at the splice instead of failing the handoff. A missing initial config stays fatal. */
  configDiffers: boolean = false;
  /** True when the splice was a forward cut to the candidate's own keyframe instead of an exact
   * same-IDR boundary. Output is monotonic either way; only the log label differs. */
  cutForward: boolean = false;
  private forwardVideoConfig: Uint8Array | null = null;
  private forwardAudioConfig: Uint8Array | null = null;
  // Boundary rejection accounting. Counts only; the relay logs them when a handoff fails so the
  // exact blocking condition is visible without guessing from raw timing.
  private diagGuard: number = 0;
  private diagNotIdr: number = 0;
  private diagNoKey: number = 0;
  private diagAdvance: number = 0;
  private diagPresentation: number = 0;
  private diagOutput: number = 0;
  private diagPassed: number = 0;
  private diagAccepted: number = 0;
  matchedPackets: number = 0;
  skippedOverlap: number = 0;
  skippedMedia: number = 0;
  skippedKeyframes: number = 0;
  contentAdvanceMs: number = 0;
  rawTimestamps: number[] = [];

  constructor(expectedVideo: number, expectedAudio: number, _lastTime: number,
    videoHeader?: Uint8Array | null, audioHeader?: Uint8Array | null, history?: FlvMediaHistory) {
    this.expectedVideo = expectedVideo;
    this.expectedAudio = expectedAudio;
    this.initialVideoHeader = videoHeader ?? null;
    this.initialAudioHeader = audioHeader ?? null;
    this.history = history ?? new FlvMediaHistory();
    this.epoch = this.history.epoch;
  }

  /** Called BEFORE admitting this old frame, after admitting every preceding frame in its chunk. */
  holdBoundary(tag: Uint8Array, raw: number, lastOutput: number): boolean {
    if (this.ready || this.boundaryRaw >= 0 || this.offset === null ||
      this.videoHeader === null || (this.expectedAudio === 10 && this.audioHeader === null)) {
      this.diagGuard++;
      return false;
    }
    if (this.history.epoch !== this.epoch) {
      this.reject('old-timeline-changed');
    }
    if (!FlvHandoff.isIdr(tag, this.videoHeader)) {
      this.diagNotIdr++;
      return false;
    }
    const key = fingerprint(tag);
    const advance = (raw - this.history.tailRaw) | 0;
    // A same-IDR boundary must also clear queued presentation time. Never shift it to hide
    // a B-frame overlap, nor select another GOP if the candidate already passed this IDR.
    if (key === '') {
      this.diagNoKey++;
      return false;
    }
    if (advance <= 0 || advance > MAX_HANDOFF_ADVANCE) {
      this.diagAdvance++;
      return false;
    }
    if (((presentation(tag, raw) - this.history.tailPresentation) | 0) <= 0) {
      this.diagPresentation++;
      return false;
    }
    if (timestamp(tag) < lastOutput) {
      this.diagOutput++;
      return false;
    }
    if (((presentation(tag, timestamp(tag)) - this.history.tailOutputPresentation) | 0) <= 0) {
      this.diagPresentation++;
      return false;
    }
    if (this.lastVideoRaw >= 0 && (((this.lastVideoRaw + this.offset - raw) | 0) >= 0)) {
      this.diagPassed++;
      return false;
    }
    this.diagAccepted++;
    this.boundaryRaw = raw;
    this.boundaryKey = key;
    this.boundaryOutput = timestamp(tag);
    this.contentAdvanceMs = advance;
    this.oldAudioRaw = this.history.audio.length > 0 ? this.history.audio[this.history.audio.length - 1].raw : -1;
    this.oldPresentation = this.history.tailPresentation;
    this.oldOutputPresentation = this.history.tailOutputPresentation;
    this.pendingReason = 'waiting-same-idr';
    return true;
  }

  push(chunk: Uint8Array, currentLastTime: number = 0, allowForwardCut: boolean = false): Uint8Array[] {
    if (!this.ready && this.history.epoch !== this.epoch) {
      this.reject('old-timeline-changed');
    }
    const out: Uint8Array[] = [];
    this.rawTimestamps = [];
    this.parser.push(chunk, (tag: Uint8Array, raw: number) => {
      const video = tag[0] === 9;
      if (tag[0] === 9 || tag[0] === 8) {
        const codec = video ? tag[11] & 15 : tag[11] >>> 4;
        if (codec !== (video ? this.expectedVideo : this.expectedAudio)) {
          this.reject('codec-mismatch');
        }
        if (tag[12] === 0 && (video || codec === 10)) {
          const initial = video ? this.initialVideoHeader : this.initialAudioHeader;
          if (initial === null) {
            this.reject('codec-config-missing');
          } else if (!FlvHandoff.equal(tag, initial)) {
            this.configDiffers = true;
            if (!this.ready) {
              // Replayed before the boundary IDR so the decoder holds the candidate's own SPS/PPS.
              if (video) {
                this.forwardVideoConfig = tag;
              } else {
                this.forwardAudioConfig = tag;
              }
            }
          }
          if (video) {
            this.videoHeader = tag;
          } else {
            this.audioHeader = tag;
          }
        }
      }
      if (!media(tag)) {
        if (this.ready) {
          out.push(setTimestamp(tag, this.outputClock.normalizeTimestamp(raw, false)));
          this.rawTimestamps.push((raw + (this.offset ?? 0)) >>> 0);
        }
        return; // Configuration/metadata are not identity evidence; no duplicate prefix at splice.
      }
      const previous = video ? this.lastVideoRaw : this.lastAudioRaw;
      if (previous >= 0 && (((raw - previous) | 0) < 0 || ((raw - previous) | 0) > HISTORY_MS)) {
        this.reject('candidate-timeline-changed');
      }
      if (video) {
        this.lastVideoRaw = raw;
      } else {
        this.lastAudioRaw = raw;
      }
      if (!this.ready) {
        const key = fingerprint(tag);
        const window = video ? this.videoWindow : this.audioWindow;
        window.push(new MediaSample(raw, key));
        if (window.length > PROOF_PACKETS) {
          window.shift();
        }
        const alreadyProved = this.offset !== null;
        if (!alreadyProved) {
          this.prove();
        }
        const mapped = (raw + (this.offset ?? 0)) >>> 0;
        if (this.offset !== null && alreadyProved && key !== '') {
          const old = video ? this.history.video : this.history.audio;
          if (old.length > 0 && ((mapped - old[0].raw) | 0) >= 0 &&
            ((mapped - old[old.length - 1].raw) | 0) <= 0) {
            if (!old.some((sample: MediaSample) => sample.raw === mapped && sample.key === key)) {
              this.reject('overlap-diverged');
            }
            this.skippedOverlap++;
          }
        }
        if (this.boundaryRaw >= 0) {
          if (!video && this.oldAudioRaw >= 0 && ((mapped - this.oldAudioRaw) | 0) > 0) {
            // Different interleaving would otherwise silently lose an unplayed audio packet.
            this.reject('audio-before-idr');
          }
          if (video && ((mapped - this.boundaryRaw) | 0) >= 0) {
            if (mapped !== this.boundaryRaw || key !== this.boundaryKey) {
              this.reject('boundary-mismatch');
            }
            this.ready = true;
            this.pendingReason = 'same-idr';
            // Inherit precisely the old IDR's decoder clock, not candidate preroll + an offset.
            this.outputClock.anchor(mapped, this.boundaryOutput);
            if (this.forwardVideoConfig !== null) {
              out.push(setTimestamp(this.forwardVideoConfig, this.boundaryOutput));
              this.rawTimestamps.push(mapped);
            }
            if (this.forwardAudioConfig !== null) {
              out.push(setTimestamp(this.forwardAudioConfig, this.boundaryOutput));
              this.rawTimestamps.push(mapped);
            }
            out.push(setTimestamp(tag, this.boundaryOutput));
            this.rawTimestamps.push(mapped);
            return;
          }
        }
        // Candidate-driven splice. This connection is parsed without the old stream's
        // normalization, history and forwarding work, so its newest frame runs marginally ahead and
        // every old keyframe arrives already discarded (device diag: passed=N accepted=0). No
        // boundary can then be held, and the attempt used to end in a full player reset - the
        // content rewind the user reports. Once the caller has given the exact splice its chance,
        // cut forward to the candidate's own keyframe: output stays monotonic, never backwards, at
        // worst one GOP of content is skipped.
        if (this.boundaryRaw < 0 && allowForwardCut && this.offset !== null && video &&
          currentLastTime > 0 && ((mapped - currentLastTime) | 0) > 0 &&
          FlvHandoff.isIdr(tag, this.videoHeader)) {
          this.ready = true;
          this.pendingReason = 'candidate-forward-cut';
          this.cutForward = true;
          this.boundaryRaw = mapped;
          this.boundaryOutput = (currentLastTime + 1) >>> 0;
          this.contentAdvanceMs = (mapped - currentLastTime) | 0;
          this.oldPresentation = mapped;
          this.oldOutputPresentation = this.boundaryOutput;
          this.oldAudioRaw = mapped;
          // Continue the decoder clock from the forwarded position, not the candidate's own time.
          this.outputClock.anchor(mapped, this.boundaryOutput);
          if (this.forwardVideoConfig !== null) {
            out.push(setTimestamp(this.forwardVideoConfig, this.boundaryOutput));
            this.rawTimestamps.push(mapped);
          }
          if (this.forwardAudioConfig !== null) {
            out.push(setTimestamp(this.forwardAudioConfig, this.boundaryOutput));
            this.rawTimestamps.push(mapped);
          }
          out.push(setTimestamp(tag, this.boundaryOutput));
          this.rawTimestamps.push(mapped);
          return;
        }
        this.skippedMedia++;
        if (video && (tag[11] >>> 4) === 1) {
          this.skippedKeyframes++;
        }
        return;
      }
      const mapped = (raw + (this.offset ?? 0)) >>> 0;
      if (!video && this.oldAudioRaw >= 0 && ((mapped - this.oldAudioRaw) | 0) <= 0) {
        // Already admitted old audio only; unplayed audio before the IDR DTS is retained.
        this.skippedOverlap++;
        return;
      }
      if (video && ((presentation(tag, mapped) - this.oldPresentation) | 0) <= 0) {
        this.reject('video-before-boundary');
      }
      const output = this.outputClock.normalizeTimestamp(mapped, true);
      if (video && ((presentation(tag, output) - this.oldOutputPresentation) | 0) <= 0) {
        this.reject('output-presentation-overlap');
      }
      out.push(setTimestamp(tag, output));
      this.rawTimestamps.push(mapped);
    });
    // Parsing never commits history: held old frames and unadmitted candidate frames are not played.
    return out;
  }

  static isIdr(tag: Uint8Array, config: Uint8Array | null): boolean {
    if (!media(tag) || tag[0] !== 9 || (tag[11] >>> 4) !== 1 || config === null || config.length < 25) {
      return false;
    }
    const lengthSize = (config[20] & 3) + 1;
    if (lengthSize === 3) {
      return false;
    }
    let idr = false;
    let pos = 16;
    const end = tag.length - 4;
    while (pos < end) {
      if (pos + lengthSize > end) {
        return false;
      }
      let size = 0;
      for (let i = 0; i < lengthSize; i++) {
        size = size * 256 + tag[pos++];
      }
      if (size < 1 || pos + size > end) {
        return false;
      }
      idr = idr || (tag[pos] & 31) === 5;
      pos += size;
    }
    return idr;
  }

  private prove(): void {
    const video = FlvMediaHistory.offsets(this.videoWindow, this.history.video);
    const audio = this.expectedAudio > 0 ?
      FlvMediaHistory.offsets(this.audioWindow, this.history.audio) : video;
    if (video.length > 1 || audio.length > 1) {
      this.pendingReason = 'ambiguous-overlap';
      return;
    }
    if (video.length !== 1 || audio.length !== 1) {
      return;
    }
    if (video[0] !== audio[0]) {
      this.pendingReason = 'audio-video-offset-mismatch';
      return;
    }
    this.offset = video[0];
    this.matchedPackets = PROOF_PACKETS * (this.expectedAudio > 0 ? 2 : 1);
    this.skippedOverlap = this.matchedPackets;
    this.pendingReason = 'waiting-old-idr';
  }

  private reject(reason: string): void {
    this.pendingReason = reason;
    throw new Error('Unsafe FLV handoff');
  }

  get firstMediaRawTimestamp(): number {
    return this.parser.firstMediaTimestamp;
  }

  /** Boundary rejection breakdown for the fallback log; numbers only. */
  boundaryDiagnostics(): string {
    return `bd guard=${this.diagGuard} notIdr=${this.diagNotIdr} noKey=${this.diagNoKey} ` +
      `advance=${this.diagAdvance} presentation=${this.diagPresentation} output=${this.diagOutput} ` +
      `passed=${this.diagPassed} accepted=${this.diagAccepted} configDiffers=${this.configDiffers}`;
  }

  get firstOutputTimestamp(): number {
    return this.ready ? this.boundaryOutput : -1;
  }

  private static equal(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 11; i < a.length - 4; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }
}
