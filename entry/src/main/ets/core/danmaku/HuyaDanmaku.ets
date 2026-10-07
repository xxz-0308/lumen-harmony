import { LiveDanmaku } from './LiveDanmaku';
import { LiveMessage, normalizeColor } from '../model/Models';
import { TarsInputStream, TarsOutputStream, TarsStruct } from '../tars/Tars';
import { Base64 } from '../common/Bytes';

export class HuyaDanmakuArgs {
  ayyuid: number = 0;
  topSid: number = 0;
  subSid: number = 0;
}

class HYSender implements TarsStruct {
  uid: number = 0;
  nickName: string = '';

  writeTo(os: TarsOutputStream): void {
  }

  readFrom(is: TarsInputStream): void {
    this.uid = is.readInt(0);
    this.nickName = is.readString(2);
  }
}

class HYBulletFormat implements TarsStruct {
  fontColor: number = 0;

  writeTo(os: TarsOutputStream): void {
  }

  readFrom(is: TarsInputStream): void {
    this.fontColor = is.readInt(0);
  }
}

class HYMessage implements TarsStruct {
  sender: HYSender = new HYSender();
  content: string = '';
  format: HYBulletFormat = new HYBulletFormat();

  writeTo(os: TarsOutputStream): void {
  }

  readFrom(is: TarsInputStream): void {
    is.readStruct(0, this.sender);
    this.content = is.readString(3);
    is.readStruct(6, this.format);
  }
}

const HEARTBEAT = Base64.decode('ABQdAAwsNgBM');

export class HuyaDanmaku extends LiveDanmaku {
  protected heartbeatMs(): number {
    // Matches the reference client; a longer gap lets the edge drop us on quiet rooms.
    return 20 * 1000;
  }

  protected serverUrl(): string {
    return 'wss://cdnws.api.huya.com';
  }

  protected onOpened(): void {
    const a = this.args as HuyaDanmakuArgs;
    const inner = new TarsOutputStream();
    inner.writeInt(a.ayyuid, 0);
    inner.writeBool(true, 1);
    inner.writeString('', 2);
    inner.writeString('', 3);
    inner.writeInt(a.topSid, 4);
    inner.writeInt(a.subSid, 5);
    inner.writeInt(0, 6);
    inner.writeInt(0, 7);
    const cmd = new TarsOutputStream();
    cmd.writeInt(1, 0);
    cmd.writeBytes(inner.toBytes(), 1);
    this.send(cmd.toBytes());
  }

  protected heartbeat(): void {
    this.send(HEARTBEAT);
  }

  protected decode(data: Uint8Array): void {
    const s = new TarsInputStream(data);
    const type = s.readInt(0);
    if (type !== 7) {
      return;
    }
    const push = new TarsInputStream(s.readBytes(1));
    push.readInt(0); // pushType
    const uri = push.readInt(1);
    const msg = push.readBytes(2);
    if (uri === 1400) {
      const m = new HYMessage();
      m.readFrom(new TarsInputStream(msg));
      if (m.content.length > 0) {
        this.emit(LiveMessage.chat(m.sender.nickName, m.content, normalizeColor(m.format.fontColor)));
      }
    } else if (uri === 8006) {
      this.emit(LiveMessage.onlineCount(new TarsInputStream(msg).readInt(0)));
    }
  }
}
