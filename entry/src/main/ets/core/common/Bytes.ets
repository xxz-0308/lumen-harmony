/**
 * Platform-independent byte helpers: UTF-8, Base64, MD5 and growable binary buffers.
 * Kept free of HarmonyOS APIs so the protocol layer can be verified under Node.
 */

export class Utf8 {
  static encode(text: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < text.length; i++) {
      let code = text.charCodeAt(i);
      if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
        const next = text.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
          i++;
        }
      }
      if (code < 0x80) {
        out.push(code);
      } else if (code < 0x800) {
        out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code < 0x10000) {
        out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      } else {
        out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      }
    }
    return new Uint8Array(out);
  }

  static decode(bytes: Uint8Array, start: number = 0, end: number = -1): string {
    const stop = end < 0 ? bytes.length : Math.min(end, bytes.length);
    const parts: string[] = [];
    let chunk: number[] = [];
    let i = start;
    while (i < stop) {
      const b0 = bytes[i];
      let code = 0xfffd;
      let size = 1;
      if (b0 < 0x80) {
        code = b0;
      } else if ((b0 & 0xe0) === 0xc0 && i + 1 < stop) {
        code = ((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f);
        size = 2;
      } else if ((b0 & 0xf0) === 0xe0 && i + 2 < stop) {
        code = ((b0 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f);
        size = 3;
      } else if ((b0 & 0xf8) === 0xf0 && i + 3 < stop) {
        code = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) | ((bytes[i + 2] & 0x3f) << 6) |
          (bytes[i + 3] & 0x3f);
        size = 4;
      }
      i += size;
      if (code >= 0x10000) {
        code -= 0x10000;
        chunk.push(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff));
      } else {
        chunk.push(code);
      }
      if (chunk.length >= 4096) {
        parts.push(String.fromCharCode(...chunk));
        chunk = [];
      }
    }
    if (chunk.length > 0) {
      parts.push(String.fromCharCode(...chunk));
    }
    return parts.join('');
  }
}

const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export class Base64 {
  static encode(bytes: Uint8Array): string {
    let out = '';
    let i = 0;
    for (; i + 2 < bytes.length; i += 3) {
      const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      out += B64_CHARS.charAt((n >> 18) & 63) + B64_CHARS.charAt((n >> 12) & 63) + B64_CHARS.charAt((n >> 6) & 63) + B64_CHARS.charAt(n & 63);
    }
    const rest = bytes.length - i;
    if (rest === 1) {
      const n = bytes[i] << 16;
      out += B64_CHARS.charAt((n >> 18) & 63) + B64_CHARS.charAt((n >> 12) & 63) + '==';
    } else if (rest === 2) {
      const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
      out += B64_CHARS.charAt((n >> 18) & 63) + B64_CHARS.charAt((n >> 12) & 63) + B64_CHARS.charAt((n >> 6) & 63) + '=';
    }
    return out;
  }

  static decode(text: string): Uint8Array {
    const clean = text.replace(/[^A-Za-z0-9+/\-_]/g, '');
    const out: number[] = [];
    let buffer = 0;
    let bits = 0;
    for (let i = 0; i < clean.length; i++) {
      let c = clean.charAt(i);
      if (c === '-') {
        c = '+';
      } else if (c === '_') {
        c = '/';
      }
      buffer = (buffer << 6) | B64_CHARS.indexOf(c);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((buffer >> bits) & 0xff);
      }
    }
    return new Uint8Array(out);
  }

  static decodeToString(text: string): string {
    return Utf8.decode(Base64.decode(text));
  }
}

// MD5 per RFC 1321, operating on bytes so that non-ASCII input is hashed as UTF-8.
const MD5_S: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];
const MD5_K: number[] = [];
for (let i = 0; i < 64; i++) {
  MD5_K.push(Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) >>> 0);
}

export class Md5 {
  static hex(text: string): string {
    return Md5.hexBytes(Utf8.encode(text));
  }

  static hexBytes(input: Uint8Array): string {
    const len = input.length;
    const total = (((len + 8) >> 6) + 1) * 64;
    const msg = new Uint8Array(total);
    msg.set(input);
    msg[len] = 0x80;
    const bitLen = len * 8;
    msg[total - 8] = bitLen & 0xff;
    msg[total - 7] = (bitLen >>> 8) & 0xff;
    msg[total - 6] = (bitLen >>> 16) & 0xff;
    msg[total - 5] = (bitLen >>> 24) & 0xff;
    const high = Math.floor(bitLen / 4294967296);
    msg[total - 4] = high & 0xff;
    msg[total - 3] = (high >>> 8) & 0xff;

    let a0 = 0x67452301;
    let b0 = 0xefcdab89;
    let c0 = 0x98badcfe;
    let d0 = 0x10325476;
    const m: number[] = new Array<number>(16).fill(0);
    for (let off = 0; off < total; off += 64) {
      for (let j = 0; j < 16; j++) {
        const p = off + j * 4;
        m[j] = (msg[p] | (msg[p + 1] << 8) | (msg[p + 2] << 16) | (msg[p + 3] << 24)) >>> 0;
      }
      let a = a0;
      let b = b0;
      let c = c0;
      let d = d0;
      for (let i = 0; i < 64; i++) {
        let f = 0;
        let g = 0;
        if (i < 16) {
          f = (b & c) | (~b & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | (~d & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | ~d);
          g = (7 * i) % 16;
        }
        const tmp = d;
        d = c;
        c = b;
        const sum = (a + f + MD5_K[i] + m[g]) >>> 0;
        b = (b + ((sum << MD5_S[i]) | (sum >>> (32 - MD5_S[i])))) >>> 0;
        a = tmp;
      }
      a0 = (a0 + a) >>> 0;
      b0 = (b0 + b) >>> 0;
      c0 = (c0 + c) >>> 0;
      d0 = (d0 + d) >>> 0;
    }
    return Md5.wordHex(a0) + Md5.wordHex(b0) + Md5.wordHex(c0) + Md5.wordHex(d0);
  }

  private static wordHex(w: number): string {
    let s = '';
    for (let i = 0; i < 4; i++) {
      const byte = (w >>> (i * 8)) & 0xff;
      s += (byte < 16 ? '0' : '') + byte.toString(16);
    }
    return s;
  }
}

const TWO_32 = 4294967296;

/** Growable big/little-endian writer. Integers up to 2^53 are supported for 64-bit fields. */
export class ByteWriter {
  private buf: Uint8Array = new Uint8Array(64);
  private len: number = 0;

  get length(): number {
    return this.len;
  }

  private ensure(extra: number): void {
    if (this.len + extra <= this.buf.length) {
      return;
    }
    let cap = this.buf.length * 2;
    while (cap < this.len + extra) {
      cap *= 2;
    }
    const next = new Uint8Array(cap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
  }

  u8(v: number): ByteWriter {
    this.ensure(1);
    this.buf[this.len++] = v & 0xff;
    return this;
  }

  u16(v: number, little: boolean = false): ByteWriter {
    this.ensure(2);
    if (little) {
      this.buf[this.len++] = v & 0xff;
      this.buf[this.len++] = (v >>> 8) & 0xff;
    } else {
      this.buf[this.len++] = (v >>> 8) & 0xff;
      this.buf[this.len++] = v & 0xff;
    }
    return this;
  }

  u32(v: number, little: boolean = false): ByteWriter {
    this.ensure(4);
    const x = v >>> 0;
    if (little) {
      this.buf[this.len++] = x & 0xff;
      this.buf[this.len++] = (x >>> 8) & 0xff;
      this.buf[this.len++] = (x >>> 16) & 0xff;
      this.buf[this.len++] = (x >>> 24) & 0xff;
    } else {
      this.buf[this.len++] = (x >>> 24) & 0xff;
      this.buf[this.len++] = (x >>> 16) & 0xff;
      this.buf[this.len++] = (x >>> 8) & 0xff;
      this.buf[this.len++] = x & 0xff;
    }
    return this;
  }

  /** Big-endian signed 64-bit integer (exact for |v| < 2^53). */
  i64(v: number): ByteWriter {
    let hi = Math.floor(v / TWO_32);
    let lo = v - hi * TWO_32;
    if (v < 0) {
      // two's complement across both words
      hi = (hi + TWO_32) % TWO_32;
      lo = (lo + TWO_32) % TWO_32;
    }
    this.u32(hi);
    this.u32(lo);
    return this;
  }

  f32(v: number): ByteWriter {
    const dv = new DataView(new ArrayBuffer(4));
    dv.setFloat32(0, v, false);
    return this.bytes(new Uint8Array(dv.buffer));
  }

  f64(v: number): ByteWriter {
    const dv = new DataView(new ArrayBuffer(8));
    dv.setFloat64(0, v, false);
    return this.bytes(new Uint8Array(dv.buffer));
  }

  bytes(b: Uint8Array): ByteWriter {
    this.ensure(b.length);
    this.buf.set(b, this.len);
    this.len += b.length;
    return this;
  }

  toBytes(): Uint8Array {
    return this.buf.slice(0, this.len);
  }
}

export class ByteReader {
  readonly data: Uint8Array;
  pos: number;

  constructor(data: Uint8Array, pos: number = 0) {
    this.data = data;
    this.pos = pos;
  }

  get remaining(): number {
    return this.data.length - this.pos;
  }

  private need(n: number): void {
    if (this.pos + n > this.data.length) {
      throw new Error(`ByteReader: need ${n} bytes at ${this.pos}, have ${this.data.length}`);
    }
  }

  u8(): number {
    this.need(1);
    return this.data[this.pos++];
  }

  i8(): number {
    const v = this.u8();
    return v > 127 ? v - 256 : v;
  }

  i16(little: boolean = false): number {
    this.need(2);
    const a = this.data[this.pos++];
    const b = this.data[this.pos++];
    const v = little ? (b << 8) | a : (a << 8) | b;
    return v > 32767 ? v - 65536 : v;
  }

  u32(little: boolean = false): number {
    this.need(4);
    const d = this.data;
    const p = this.pos;
    this.pos += 4;
    if (little) {
      return (d[p] | (d[p + 1] << 8) | (d[p + 2] << 16) | (d[p + 3] << 24)) >>> 0;
    }
    return ((d[p] << 24) | (d[p + 1] << 16) | (d[p + 2] << 8) | d[p + 3]) >>> 0;
  }

  i32(little: boolean = false): number {
    return this.u32(little) | 0;
  }

  /** Big-endian signed 64-bit integer, precise up to 2^53. */
  i64(): number {
    const hi = this.u32();
    const lo = this.u32();
    if (hi >= 0x80000000) {
      return -((TWO_32 - 1 - hi) * TWO_32 + (TWO_32 - lo));
    }
    return hi * TWO_32 + lo;
  }

  f32(): number {
    this.need(4);
    const dv = new DataView(this.data.buffer, this.data.byteOffset + this.pos, 4);
    this.pos += 4;
    return dv.getFloat32(0, false);
  }

  f64(): number {
    this.need(8);
    const dv = new DataView(this.data.buffer, this.data.byteOffset + this.pos, 8);
    this.pos += 8;
    return dv.getFloat64(0, false);
  }

  bytes(n: number): Uint8Array {
    this.need(n);
    const out = this.data.slice(this.pos, this.pos + n);
    this.pos += n;
    return out;
  }

  skip(n: number): void {
    this.need(n);
    this.pos += n;
  }
}

export function randomHex(length: number): string {
  let s = '';
  for (let i = 0; i < length; i++) {
    s += Math.floor(Math.random() * 16).toString(16);
  }
  return s;
}
