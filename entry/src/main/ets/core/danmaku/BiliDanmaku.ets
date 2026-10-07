import { LiveDanmaku } from './LiveDanmaku';
import { LiveMessage, normalizeColor, SuperChatMessage } from '../model/Models';
import { httpsUrl } from '../common/Http';
import { ByteReader, ByteWriter, Utf8 } from '../common/Bytes';
import { JNode } from '../common/Json';
import { Platform } from '../common/Transport';

export class BiliDanmakuArgs {
  roomId: number = 0;
  uid: number = 0;
  token: string = '';
  host: string = 'broadcastlv.chat.bilibili.com';
  buvid: string = '';
}

const OP_HEARTBEAT = 2;
const OP_HEARTBEAT_REPLY = 3;
const OP_MESSAGE = 5;
const OP_AUTH = 7;

export class BiliDanmaku extends LiveDanmaku {
  protected heartbeatMs(): number {
    return 30 * 1000;
  }

  protected serverUrl(): string {
    return `wss://${(this.args as BiliDanmakuArgs).host}/sub`;
  }

  protected headers(): Record<string, string> {
    return {};
  }

  static packet(body: string, op: number): Uint8Array {
    const data = Utf8.encode(body);
    const w = new ByteWriter();
    w.u32(data.length + 16);
    w.u16(16);
    w.u16(1);
    w.u32(op);
    w.u32(1);
    w.bytes(data);
    return w.toBytes();
  }

  protected onOpened(): void {
    const a = this.args as BiliDanmakuArgs;
    // protover 2 = zlib; avoids needing a brotli decoder on device
    const auth = `{"uid":${a.uid},"roomid":${a.roomId},"protover":2,"buvid":${JSON.stringify(a.buvid)},` +
      `"platform":"web","type":2,"key":${JSON.stringify(a.token)}}`;
    this.send(BiliDanmaku.packet(auth, OP_AUTH));
    this.heartbeat();
  }

  protected heartbeat(): void {
    this.send(BiliDanmaku.packet('', OP_HEARTBEAT));
  }

  protected decode(data: Uint8Array): void {
    const r = new ByteReader(data);
    while (r.remaining >= 16) {
      const start = r.pos;
      const len = r.u32();
      const headerLen = r.i16();
      const ver = r.i16();
      const op = r.u32();
      r.u32();
      // A zero-length/zero-header frame would not advance the cursor and hangs the loop.
      if (headerLen < 16 || len < headerLen || start + len > data.length) {
        return;
      }
      r.pos = start + headerLen;
      const body = r.bytes(len - headerLen);
      if (op === OP_HEARTBEAT_REPLY && body.length >= 4) {
        this.emit(LiveMessage.onlineCount(new ByteReader(body).u32()));
      } else if (op === OP_MESSAGE) {
        if (ver === 2) {
          this.decode(Platform.inflater.inflate(body));
        } else if (ver === 0 || ver === 1) {
          this.handleJson(Utf8.decode(body));
        }
      }
    }
  }

  private handleJson(text: string): void {
    const obj = JNode.tryParse(text);
    const cmd = obj.get('cmd').str();
    if (cmd.startsWith('DANMU_MSG')) {
      const info = obj.get('info');
      const content = info.at(1).str();
      const user = info.at(2).at(1).str();
      if (content.length > 0) {
        this.emit(LiveMessage.chat(user, content, normalizeColor(info.at(0).at(3).int())));
      }
    } else if (cmd === 'SUPER_CHAT_MESSAGE') {
      const data = obj.get('data');
      if (data.exists) {
        this.emit(LiveMessage.sc(parseBiliSuperChat(data)));
      }
    }
  }
}

export function parseBiliSuperChat(it: JNode): SuperChatMessage {
  const sc = new SuperChatMessage();
  sc.userName = it.path('user_info.uname').str();
  sc.face = `${httpsUrl(it.path('user_info.face').str())}@100w.jpg`;
  sc.message = it.get('message').str();
  sc.price = it.get('price').num();
  sc.startTime = it.get('start_time').int();
  sc.endTime = it.get('end_time').int();
  sc.backgroundColor = it.get('background_color').str('#EDF5FF');
  sc.backgroundBottomColor = it.get('background_bottom_color').str('#2A60B2');
  return sc;
}
