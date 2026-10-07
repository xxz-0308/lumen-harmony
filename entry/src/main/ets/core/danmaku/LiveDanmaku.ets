import { LiveMessage } from '../model/Models';
import { Platform, WsConnection, WsListener } from '../common/Transport';

export type MessageHandler = (msg: LiveMessage) => void;
export type StatusHandler = (text: string) => void;

/**
 * Base class for platform danmaku clients: owns the socket, heartbeat and bounded reconnects.
 * Subclasses only encode the join/heartbeat frames and decode incoming payloads.
 */
export abstract class LiveDanmaku {
  onMessage: MessageHandler | null = null;
  onStatus: StatusHandler | null = null;
  onReady: (() => void) | null = null;

  protected conn: WsConnection | null = null;
  private heartbeatTimer: number = -1;
  private reconnectTimer: number = -1;
  private stableTimer: number = -1;
  private authTimer: number = -1;
  private ready: boolean = false;
  private reconnectCount: number = 0;
  private stopped: boolean = true;
  private generation: number = 0;
  protected args: Object | null = null;

  protected abstract heartbeatMs(): number;

  protected abstract serverUrl(): string;

  protected headers(): Record<string, string> {
    return {};
  }

  protected abstract onOpened(): void;

  protected readyOnOpen(): boolean {
    return true;
  }

  protected announceReady(): void {
    if (this.stopped || this.ready) {
      return;
    }
    this.ready = true;
    if (this.authTimer >= 0) {
      Platform.timers.clearTimeout(this.authTimer);
      this.authTimer = -1;
    }
    this.onReady?.();
    const gen = this.generation;
    // A single packet does not establish a stable session; reset backoff only after 20s.
    this.stableTimer = Platform.timers.setTimeout(() => {
      this.stableTimer = -1;
      if (gen === this.generation) {
        this.reconnectCount = 0;
      }
    }, 20000);
  }

  protected abstract heartbeat(): void;

  protected abstract decode(data: Uint8Array): void;

  protected decodeText(text: string): void {
  }

  start(args: Object | null): void {
    this.args = args;
    this.stopped = false;
    this.reconnectCount = 0;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    this.generation++;
    this.onMessage = null;
    this.onStatus = null;
    this.onReady = null;
    this.clearTimers();
    const c = this.conn;
    this.conn = null;
    c?.close();
  }

  protected emit(msg: LiveMessage): void {
    this.onMessage?.(msg);
  }

  protected send(data: Uint8Array): void {
    this.conn?.sendBinary(data);
  }

  private clearTimers(): void {
    if (this.heartbeatTimer >= 0) {
      Platform.timers.clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
    if (this.reconnectTimer >= 0) {
      Platform.timers.clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    if (this.stableTimer >= 0) {
      Platform.timers.clearTimeout(this.stableTimer);
      this.stableTimer = -1;
    }
    if (this.authTimer >= 0) {
      Platform.timers.clearTimeout(this.authTimer);
      this.authTimer = -1;
    }
  }

  private connect(): void {
    this.clearTimers();
    this.ready = false;
    const gen = ++this.generation;
    const listener: WsListener = {
      onOpen: () => {
        if (gen !== this.generation) {
          return;
        }
        this.onOpened();
        if (this.readyOnOpen()) {
          this.announceReady();
        } else if (!this.ready) {
          this.authTimer = Platform.timers.setTimeout(() => {
            this.authTimer = -1;
            if (gen === this.generation && !this.ready) {
              this.scheduleReconnect('弹幕登录确认超时');
            }
          }, 10000);
        }
        this.heartbeatTimer = Platform.timers.setInterval(() => {
          if (gen === this.generation) {
            this.heartbeat();
          }
        }, this.heartbeatMs());
      },
      onBinary: (data: Uint8Array) => {
        if (gen !== this.generation) {
          return;
        }
        try {
          this.decode(data);
        } catch (e) {
          Platform.log(`[danmaku] decode error ${e}`);
        }
      },
      onText: (text: string) => {
        if (gen === this.generation) {
          this.decodeText(text);
        }
      },
      onClose: (reason: string) => {
        if (gen === this.generation) {
          this.scheduleReconnect(reason);
        }
      },
      onError: (err: string) => {
        if (gen === this.generation) {
          this.scheduleReconnect(err);
        }
      }
    };
    try {
      this.conn = Platform.ws.connect(this.serverUrl(), this.headers(), listener);
    } catch (e) {
      this.scheduleReconnect(`${e}`);
    }
  }

  private scheduleReconnect(reason: string): void {
    if (this.stopped) {
      return;
    }
    this.generation++;
    this.clearTimers();
    const old = this.conn;
    this.conn = null;
    old?.close();
    this.reconnectCount++;
    if (this.reconnectCount > 5) {
      // Idle rooms are closed by the server; keep trying at a slow pace instead of dying.
      this.onStatus?.('弹幕连接已断开，稍后重试');
      Platform.log(`[danmaku] slow retry after ${reason}`);
      this.reconnectTimer = Platform.timers.setTimeout(() => {
        this.reconnectTimer = -1;
        if (!this.stopped) {
          this.reconnectCount = 5;
          this.connect();
        }
      }, 30000);
      return;
    }
    this.onStatus?.(`弹幕重连中（${this.reconnectCount}）`);
    Platform.log(`[danmaku] reconnect #${this.reconnectCount}: ${reason}`);
    this.reconnectTimer = Platform.timers.setTimeout(() => {
      this.reconnectTimer = -1;
      if (!this.stopped) {
        this.connect();
      }
    }, 1500 * this.reconnectCount);
  }
}
