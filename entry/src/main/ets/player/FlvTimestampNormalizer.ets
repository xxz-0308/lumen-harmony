const MAX_HEADER = 4096;
const MAX_TAG = 8 * 1024 * 1024;
const MAX_PENDING = MAX_TAG + MAX_HEADER + 15;
const MAX_FORWARD_STEP = 60000;
const MAX_REORDER = 2000;

function read24(b: Uint8Array, i: number): number {
  return b[i] * 65536 + b[i + 1] * 256 + b[i + 2];
}

function read32(b: Uint8Array, i: number): number {
  return (b[i] * 16777216 + b[i + 1] * 65536 + b[i + 2] * 256 + b[i + 3]) >>> 0;
}

/** Incremental FLV parser. Changes only tag timestamps; never buffers a complete live stream. */
export class FlvTimestampNormalizer {
  private pending: Uint8Array = new Uint8Array(0);
  private headerDone: boolean = false;
  private lastRaw: number = -1;
  private lastOutput: number = 0;
  private reorderRun: number = 0;
  firstMediaTimestamp: number = -1;
  // Parallel to the returned frames; -1 denotes the FLV header. Parsing is NOT admission.
  rawTimestamps: number[] = [];

  /** Continue at an identical IDR's old output clock, including subsequent same-chunk tags. */
  anchor(raw: number, output: number): void {
    this.lastRaw = raw;
    this.lastOutput = output;
    this.reorderRun = 0;
  }

  push(chunk: Uint8Array, observe?: (tag: Uint8Array, rawTimestamp: number) => void): Uint8Array[] {
    this.rawTimestamps = [];
    if (chunk.length + this.pending.length > MAX_PENDING) {
      throw new Error('FLV tag exceeds buffer limit');
    }
    const data = new Uint8Array(this.pending.length + chunk.length);
    data.set(this.pending);
    data.set(chunk, this.pending.length);
    const out: Uint8Array[] = [];
    let offset = 0;
    if (!this.headerDone) {
      if (data.length < 9) {
        this.pending = data;
        return out;
      }
      if (data[0] !== 0x46 || data[1] !== 0x4c || data[2] !== 0x56 || data[3] !== 1) {
        throw new Error('Not an FLV stream');
      }
      const headerSize = read32(data, 5);
      if (headerSize < 9 || headerSize > MAX_HEADER) {
        throw new Error('Invalid FLV header size');
      }
      if (data.length < headerSize + 4) {
        this.pending = data;
        return out;
      }
      if (read32(data, headerSize) !== 0) {
        throw new Error('Invalid first FLV tag size');
      }
      offset = headerSize + 4;
      out.push(data.slice(0, offset));
      this.rawTimestamps.push(-1);
      this.headerDone = true;
    }
    while (data.length - offset >= 11) {
      const type = data[offset];
      if (type !== 8 && type !== 9 && type !== 18) {
        throw new Error('Invalid FLV tag type');
      }
      const size = read24(data, offset + 1);
      if (size > MAX_TAG) {
        throw new Error('FLV tag exceeds size limit');
      }
      const total = 11 + size + 4;
      if (data.length - offset < total) {
        break;
      }
      if (read32(data, offset + 11 + size) !== 11 + size) {
        throw new Error('Invalid FLV previous tag size');
      }
      const tag = data.slice(offset, offset + total);
      const raw = (read24(tag, 4) + tag[7] * 16777216) >>> 0;
      const isSequence = (type === 9 && size > 1 && tag[12] === 0) ||
        (type === 8 && size > 1 && (tag[11] >>> 4) === 10 && tag[12] === 0);
      const media = (type === 8 || type === 9) && !isSequence;
      const timestamp = this.normalizeTimestamp(raw, media);
      tag[4] = (timestamp >>> 16) & 255;
      tag[5] = (timestamp >>> 8) & 255;
      tag[6] = timestamp & 255;
      tag[7] = (timestamp >>> 24) & 255;
      out.push(tag);
      this.rawTimestamps.push(raw);
      // Raw parsing evidence only. The relay commits history after downstream queue admission.
      observe?.(tag, raw);
      offset += total;
    }
    this.pending = data.slice(offset);
    return out;
  }

  normalizeTimestamp(raw: number, media: boolean): number {
    // Metadata/sequence headers must neither count as nor interrupt media reordering.
    if (!media) {
      return this.lastOutput;
    }
    if (this.firstMediaTimestamp < 0) {
      this.firstMediaTimestamp = raw;
    }
    if (this.lastRaw < 0) {
      if (media) {
        this.lastRaw = raw;
      }
      return 0;
    }
    // Signed subtraction handles the FLV timestamp's 32-bit wraparound.
    const delta = (raw - this.lastRaw) | 0;
    if (delta >= 0 && delta <= MAX_FORWARD_STEP) {
      this.reorderRun = 0;
      if (media) {
        this.lastRaw = raw;
        this.lastOutput += delta;
      }
      // Script/metadata tags never lead the media timeline, or later media would go backwards.
      return this.lastOutput;
    }
    if (delta < 0 && delta >= -MAX_REORDER) {
      // A CDN can shift its segment timeline back; after a couple of these the raw anchor is
      // stale, so resync instead of stamping every following tag with the same time.
      if (++this.reorderRun >= 2) {
        this.reorderRun = 0;
        if (media) {
          this.lastRaw = raw;
          this.lastOutput++;
        }
      }
      return this.lastOutput;
    }
    this.reorderRun = 0;
    if (media) {
      // A CDN timestamp reset/jump must not stall the decoder for hours.
      this.lastRaw = raw;
      this.lastOutput++;
    }
    return this.lastOutput;
  }
}
