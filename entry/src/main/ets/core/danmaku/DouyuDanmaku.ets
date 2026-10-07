import { LiveDanmaku } from './LiveDanmaku';
import { LiveMessage, WHITE } from '../model/Models';
import { ByteReader, ByteWriter, Utf8 } from '../common/Bytes';
import { Platform } from '../common/Transport';

const COLORS: number[] = [WHITE, 0xff0000, 0x1e87f0, 0x7ac84b, 0xff7f00, 0x9b39f4, 0xff69b4];

export class DouyuDanmaku extends LiveDanmaku {
  private frames: number = 0;
  private packets: number = 0;
  private chats: number = 0;
  private emitted: number = 0;
  private heartbeats: number = 0;
  private groupSent: boolean = false;

  protected heartbeatMs(): number {
    // The edge closes idle sockets after ~30s; 15s keeps us comfortably inside that.
    return 15 * 1000;
  }

  protected serverUrl(): string {
    return 'wss://danmuproxy.douyu.com:8506';
  }

  protected readyOnOpen(): boolean {
    return false;
  }

  protected onOpened(): void {
    const rid = this.args as string;
    this.frames = 0;
    this.packets = 0;
    this.chats = 0;
    this.emitted = 0;
    this.heartbeats = 0;
    this.groupSent = false;
    Platform.log(`[danmaku] douyu open room=${rid}`);
    this.send(DouyuDanmaku.pack(`type@=loginreq/roomid@=${rid}/`));
    // The native WebSocket sends asynchronously; joining before login is processed can leave
    // an authenticated but unsubscribed socket. Wait for loginres before sending joingroup.
  }

  protected heartbeat(): void {
    // First summary at 15s, then once a minute; never log chat text or sender identifiers.
    if (this.heartbeats++ % 4 === 0) {
      Platform.log(`[danmaku] douyu rx room=${this.args as string} groupSent=${this.groupSent} frames=${this.frames} packets=${this.packets} chats=${this.chats} emitted=${this.emitted}`);
    }
    this.send(DouyuDanmaku.pack('type@=mrkl/'));
  }

  static pack(body: string): Uint8Array {
    const b = Utf8.encode(body);
    const len = 4 + 4 + b.length + 1;
    const w = new ByteWriter();
    w.u32(len, true);
    w.u32(len, true);
    w.u16(689, true);
    w.u8(0);
    w.u8(0);
    w.bytes(b);
    w.u8(0);
    return w.toBytes();
  }

  protected decode(data: Uint8Array): void {
    // one websocket frame may carry several STT packets
    this.frames++;
    const r = new ByteReader(data);
    while (r.remaining >= 12) {
      const full = r.u32(true);
      r.u32(true);
      r.i16(true);
      r.u8();
      r.u8();
      const bodyLen = full - 9;
      if (bodyLen < 0 || bodyLen > r.remaining) {
        return;
      }
      const text = Utf8.decode(r.bytes(bodyLen));
      if (r.remaining > 0) {
        r.u8();
      }
      this.handle(text);
    }
  }

  private handle(text: string): void {
    const obj = DouyuDanmaku.sttToMap(text);
    this.packets++;
    if (this.packets <= 3) {
      Platform.log(`[danmaku] douyu packet room=${this.args as string} type=${obj.get('type') ?? 'unknown'}`);
    }
    if (obj.get('type') === 'loginres') {
      if ((obj.get('error') ?? '0') === '0' && !this.groupSent) {
        const rid = this.args as string;
        this.groupSent = true;
        this.send(DouyuDanmaku.pack(`type@=joingroup/rid@=${rid}/gid@=-9999/`));
        Platform.log(`[danmaku] douyu group requested room=${rid}`);
        this.announceReady();
      }
      return;
    }
    if (obj.get('type') !== 'chatmsg') {
      return;
    }
    this.chats++;
    // messages without dms are system-injected noise
    if (!obj.has('dms')) {
      return;
    }
    // A real chat message also proves the group joined if an edge omitted loginres.
    this.announceReady();
    const col = Number(obj.get('col') ?? '0');
    this.emitted++;
    this.emit(LiveMessage.chat(obj.get('nn') ?? '', obj.get('txt') ?? '',
      col > 0 && col < COLORS.length ? COLORS[col] : WHITE));
  }

  /** Flat STT decode (nested values are kept as raw strings, which is all chat needs). */
  static sttToMap(text: string): Map<string, string> {
    const out = new Map<string, string>();
    const fields = text.split('/');
    for (const f of fields) {
      const idx = f.indexOf('@=');
      if (idx <= 0) {
        continue;
      }
      out.set(f.substring(0, idx), f.substring(idx + 2).replace(/@S/g, '/').replace(/@A/g, '@'));
    }
    return out;
  }
}
