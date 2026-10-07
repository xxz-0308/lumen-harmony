import { ByteReader, ByteWriter, Utf8 } from '../common/Bytes';

/** Tars wire types. */
export enum TarsType {
  BYTE = 0,
  SHORT = 1,
  INT = 2,
  LONG = 3,
  FLOAT = 4,
  DOUBLE = 5,
  STRING1 = 6,
  STRING4 = 7,
  MAP = 8,
  LIST = 9,
  STRUCT_BEGIN = 10,
  STRUCT_END = 11,
  ZERO_TAG = 12,
  SIMPLE_LIST = 13
}

export interface TarsStruct {
  writeTo(os: TarsOutputStream): void;

  readFrom(is: TarsInputStream): void;
}

export class TarsOutputStream {
  private w: ByteWriter = new ByteWriter();

  private head(type: number, tag: number): void {
    if (tag < 15) {
      this.w.u8((tag << 4) | type);
    } else {
      this.w.u8((15 << 4) | type);
      this.w.u8(tag);
    }
  }

  writeInt(n: number, tag: number): void {
    if (n === 0) {
      this.head(TarsType.ZERO_TAG, tag);
    } else if (n >= -128 && n <= 127) {
      this.head(TarsType.BYTE, tag);
      this.w.u8(n);
    } else if (n >= -32768 && n <= 32767) {
      this.head(TarsType.SHORT, tag);
      this.w.u16(n & 0xffff);
    } else if (n >= -2147483648 && n <= 2147483647) {
      this.head(TarsType.INT, tag);
      this.w.u32(n >>> 0);
    } else {
      this.head(TarsType.LONG, tag);
      this.w.i64(n);
    }
  }

  writeBool(b: boolean, tag: number): void {
    this.writeInt(b ? 1 : 0, tag);
  }

  writeString(s: string, tag: number): void {
    const bytes = Utf8.encode(s);
    if (bytes.length > 255) {
      this.head(TarsType.STRING4, tag);
      this.w.u32(bytes.length);
    } else {
      this.head(TarsType.STRING1, tag);
      this.w.u8(bytes.length);
    }
    this.w.bytes(bytes);
  }

  writeBytes(b: Uint8Array, tag: number): void {
    this.head(TarsType.SIMPLE_LIST, tag);
    this.head(TarsType.BYTE, 0);
    this.writeInt(b.length, 0);
    this.w.bytes(b);
  }

  writeStruct(s: TarsStruct, tag: number): void {
    this.head(TarsType.STRUCT_BEGIN, tag);
    s.writeTo(this);
    this.head(TarsType.STRUCT_END, 0);
  }

  writeStringMap(m: Map<string, string>, tag: number): void {
    this.head(TarsType.MAP, tag);
    this.writeInt(m.size, 0);
    m.forEach((v: string, k: string) => {
      this.writeString(k, 0);
      this.writeString(v, 1);
    });
  }

  writeBytesMap(m: Map<string, Uint8Array>, tag: number): void {
    this.head(TarsType.MAP, tag);
    this.writeInt(m.size, 0);
    m.forEach((v: Uint8Array, k: string) => {
      this.writeString(k, 0);
      this.writeBytes(v, 1);
    });
  }

  toBytes(): Uint8Array {
    return this.w.toBytes();
  }
}

class Head {
  type: number = 0;
  tag: number = 0;
  size: number = 0;
}

export class TarsInputStream {
  private r: ByteReader;

  constructor(data: Uint8Array, pos: number = 0) {
    this.r = new ByteReader(data, pos);
  }

  private peekHead(): Head {
    const h = new Head();
    const d = this.r.data;
    const p = this.r.pos;
    const b = d[p];
    h.type = b & 0x0f;
    h.tag = (b & 0xf0) >> 4;
    h.size = 1;
    if (h.tag === 15) {
      h.tag = d[p + 1];
      h.size = 2;
    }
    return h;
  }

  private readHead(): Head {
    const h = this.peekHead();
    this.r.skip(h.size);
    return h;
  }

  /** Positions the stream right after the head of `tag`; returns the wire type or -1 if absent. */
  private skipToTag(tag: number): number {
    while (this.r.remaining > 0) {
      const h = this.peekHead();
      if (h.type === TarsType.STRUCT_END) {
        return -1;
      }
      if (h.tag > tag) {
        return -1;
      }
      this.r.skip(h.size);
      if (h.tag === tag) {
        return h.type;
      }
      this.skipField(h.type);
    }
    return -1;
  }

  private skipStructBody(): void {
    while (true) {
      const h = this.readHead();
      if (h.type === TarsType.STRUCT_END) {
        return;
      }
      this.skipField(h.type);
    }
  }

  private skipField(type: number): void {
    switch (type) {
      case TarsType.BYTE:
        this.r.skip(1);
        break;
      case TarsType.SHORT:
        this.r.skip(2);
        break;
      case TarsType.INT:
      case TarsType.FLOAT:
        this.r.skip(4);
        break;
      case TarsType.LONG:
      case TarsType.DOUBLE:
        this.r.skip(8);
        break;
      case TarsType.STRING1:
        this.r.skip(this.r.u8());
        break;
      case TarsType.STRING4:
        this.r.skip(this.r.u32());
        break;
      case TarsType.MAP: {
        const n = this.readIntValue();
        for (let i = 0; i < n * 2; i++) {
          const h = this.readHead();
          this.skipField(h.type);
        }
        break;
      }
      case TarsType.LIST: {
        const n = this.readIntValue();
        for (let i = 0; i < n; i++) {
          const h = this.readHead();
          this.skipField(h.type);
        }
        break;
      }
      case TarsType.SIMPLE_LIST: {
        this.readHead();
        const n = this.readIntValue();
        this.r.skip(n);
        break;
      }
      case TarsType.STRUCT_BEGIN:
        this.skipStructBody();
        break;
      case TarsType.STRUCT_END:
      case TarsType.ZERO_TAG:
        break;
      default:
        throw new Error(`tars: invalid type ${type}`);
    }
  }

  /** Reads an integer field value whose head has already been consumed (used for lengths). */
  private readIntValue(): number {
    const h = this.readHead();
    return this.intOfType(h.type);
  }

  private intOfType(type: number): number {
    switch (type) {
      case TarsType.ZERO_TAG:
        return 0;
      case TarsType.BYTE:
        return this.r.i8();
      case TarsType.SHORT:
        return this.r.i16();
      case TarsType.INT:
        return this.r.i32();
      case TarsType.LONG:
        return this.r.i64();
      default:
        throw new Error(`tars: type ${type} is not an integer`);
    }
  }

  readInt(tag: number, def: number = 0): number {
    const t = this.skipToTag(tag);
    if (t < 0) {
      return def;
    }
    if (t === TarsType.FLOAT) {
      return this.r.f32();
    }
    if (t === TarsType.DOUBLE) {
      return this.r.f64();
    }
    return this.intOfType(t);
  }

  readBool(tag: number, def: boolean = false): boolean {
    return this.readInt(tag, def ? 1 : 0) !== 0;
  }

  readString(tag: number, def: string = ''): string {
    const t = this.skipToTag(tag);
    if (t < 0) {
      return def;
    }
    let len = 0;
    if (t === TarsType.STRING1) {
      len = this.r.u8();
    } else if (t === TarsType.STRING4) {
      len = this.r.u32();
    } else {
      this.skipField(t);
      return def;
    }
    return Utf8.decode(this.r.bytes(len));
  }

  readBytes(tag: number): Uint8Array {
    const t = this.skipToTag(tag);
    if (t < 0) {
      return new Uint8Array(0);
    }
    if (t === TarsType.SIMPLE_LIST) {
      this.readHead();
      const n = this.readIntValue();
      return this.r.bytes(n);
    }
    if (t === TarsType.LIST) {
      const n = this.readIntValue();
      const out = new Uint8Array(n);
      for (let i = 0; i < n; i++) {
        const h = this.readHead();
        out[i] = this.intOfType(h.type) & 0xff;
      }
      return out;
    }
    this.skipField(t);
    return new Uint8Array(0);
  }

  readStruct<T extends TarsStruct>(tag: number, target: T): T {
    const t = this.skipToTag(tag);
    if (t !== TarsType.STRUCT_BEGIN) {
      if (t >= 0) {
        this.skipField(t);
      }
      return target;
    }
    target.readFrom(this);
    this.skipStructBody();
    return target;
  }

  readStringMap(tag: number): Map<string, string> {
    const out = new Map<string, string>();
    const t = this.skipToTag(tag);
    if (t !== TarsType.MAP) {
      return out;
    }
    const n = this.readIntValue();
    for (let i = 0; i < n; i++) {
      const k = this.readString(0);
      const v = this.readString(1);
      out.set(k, v);
    }
    return out;
  }

  readBytesMap(tag: number): Map<string, Uint8Array> {
    const out = new Map<string, Uint8Array>();
    const t = this.skipToTag(tag);
    if (t !== TarsType.MAP) {
      return out;
    }
    const n = this.readIntValue();
    for (let i = 0; i < n; i++) {
      const k = this.readString(0);
      const v = this.readBytes(1);
      out.set(k, v);
    }
    return out;
  }
}

/** Minimal TUP3 (UniPacket) client used by Huya's wup endpoint. */
export class TupPacket {
  static encode(servant: string, func: string, reqName: string, req: TarsStruct): Uint8Array {
    const body = new TarsOutputStream();
    body.writeStruct(req, 0);
    const data = new Map<string, Uint8Array>();
    data.set(reqName, body.toBytes());
    const buf = new TarsOutputStream();
    buf.writeBytesMap(data, 0);

    const os = new TarsOutputStream();
    os.writeInt(3, 1); // iVersion = TUP3
    os.writeInt(0, 2); // cPacketType
    os.writeInt(0, 3); // iMessageType
    os.writeInt(0, 4); // iRequestId
    os.writeString(servant, 5);
    os.writeString(func, 6);
    os.writeBytes(buf.toBytes(), 7);
    os.writeInt(0, 8); // iTimeout
    os.writeStringMap(new Map<string, string>(), 9);
    os.writeStringMap(new Map<string, string>(), 10);
    const packet = os.toBytes();
    const w = new ByteWriter();
    w.u32(packet.length + 4);
    w.bytes(packet);
    return w.toBytes();
  }

  /** Decodes a TUP3 response and returns the raw value bytes keyed by name. */
  static decode(bytes: Uint8Array): Map<string, Uint8Array> {
    const is = new TarsInputStream(bytes, 4);
    const sBuffer = is.readBytes(7);
    return new TarsInputStream(sBuffer).readBytesMap(0);
  }

  static readValue<T extends TarsStruct>(values: Map<string, Uint8Array>, name: string, target: T): T {
    const raw = values.get(name);
    if (raw === undefined) {
      return target;
    }
    return new TarsInputStream(raw).readStruct(0, target);
  }
}
