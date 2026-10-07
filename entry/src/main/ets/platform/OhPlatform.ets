import { http, webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  HttpRequest,
  HttpResponse,
  HttpTransport,
  Inflater,
  Platform,
  TimerHost,
  WsConnection,
  WsListener,
  WsTransport
} from '../core/common/Transport';
import { Inflate } from '../core/common/Inflate';
import { Utf8 } from '../core/common/Bytes';
import { Log } from '../util/Log';

function toArrayBuffer(b: Uint8Array): ArrayBuffer {
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer;
}

class OhHttp implements HttpTransport {
  async send(req: HttpRequest): Promise<HttpResponse> {
    const client = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: req.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: req.headers,
        connectTimeout: req.timeoutMs,
        readTimeout: req.timeoutMs,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false
      };
      if (req.bodyBytes !== undefined) {
        opts.extraData = toArrayBuffer(req.bodyBytes);
      } else if (req.body !== undefined) {
        opts.extraData = req.body;
      }
      const r = await client.request(req.url, opts);
      const res = new HttpResponse();
      res.status = r.responseCode as number;
      const headers = (r.header ?? {}) as Record<string, Object>;
      for (const key of Object.keys(headers)) {
        const value = headers[key];
        if (typeof value === 'string') {
          if (key.toLowerCase() === 'set-cookie') {
            res.setCookies.push(value);
          } else {
            res.headers[key.toLowerCase()] = value;
          }
        } else if (Array.isArray(value)) {
          const list = value as string[];
          if (key.toLowerCase() === 'set-cookie') {
            res.setCookies = res.setCookies.concat(list);
          } else {
            res.headers[key.toLowerCase()] = list.join(', ');
          }
        }
      }
      if (typeof r.cookies === 'string' && r.cookies.length > 0) {
        res.setCookies.push(r.cookies);
      }
      const raw = r.result instanceof ArrayBuffer ? new Uint8Array(r.result as ArrayBuffer) :
        Utf8.encode(String(r.result));
      if (req.binary) {
        res.bytes = raw;
      } else {
        res.text = Utf8.decode(raw);
      }
      return res;
    } finally {
      client.destroy();
    }
  }
}

class OhWsConnection implements WsConnection {
  private ws: webSocket.WebSocket;
  private open: boolean = false;
  private closed: boolean = false;
  private detached: boolean = false;

  constructor(ws: webSocket.WebSocket) {
    this.ws = ws;
  }

  markOpen(): void {
    this.open = true;
  }

  markClosed(): void {
    this.open = false;
    this.closed = true;
    this.detach();
  }

  /** Removes the native listeners; safe to call more than once. */
  private detach(): void {
    if (this.detached) {
      return;
    }
    this.detached = true;
    this.ws.off('open');
    this.ws.off('message');
    this.ws.off('close');
    this.ws.off('error');
  }

  sendBinary(data: Uint8Array): void {
    if (this.open) {
      this.ws.send(toArrayBuffer(data)).catch((e: BusinessError) => Log.w('ws', `send failed ${e.code}`));
    }
  }

  sendText(text: string): void {
    if (this.open) {
      this.ws.send(text).catch((e: BusinessError) => Log.w('ws', `send failed ${e.code}`));
    }
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.markClosed();
    this.ws.close().catch(() => {
    });
  }
}

class OhWs implements WsTransport {
  connect(url: string, headers: Record<string, string>, l: WsListener): WsConnection {
    const ws = webSocket.createWebSocket();
    const conn = new OhWsConnection(ws);
    let frames = 0;
    ws.on('open', () => {
      Log.i('ws', `open ${url.split('?')[0]}`);
      conn.markOpen();
      l.onOpen();
    });
    ws.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
      if (err) {
        l.onError(`message ${err.code ?? 0}`);
        return;
      }
      if (data instanceof ArrayBuffer) {
        const u8 = new Uint8Array(data as ArrayBuffer);
        frames++;
        l.onBinary(u8);
      } else {
        frames++;
        l.onText(data as string);
      }
    });
    ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      conn.markClosed();
      Log.i('ws', `close ${value?.code} ${value?.reason} after ${frames} frames`);
      l.onClose(`close ${value?.code ?? 0} ${value?.reason ?? ''}`);
    });
    ws.on('error', (err: BusinessError) => {
      Log.i('ws', `error ${err?.code} ${err?.message} after ${frames} frames`);
      l.onError(`error ${err?.code ?? ''} ${err?.message ?? ''}`);
    });
    const options: webSocket.WebSocketRequestOptions = { header: headers };
    // Douyu has its own STT heartbeat; its edge drops the native default Ping/Pong at ~30s.
    // Keep the previous WebSocket policy for Huya and Bilibili.
    if (url.startsWith('wss://danmuproxy.douyu.com:')) {
      options.pingInterval = 0;
    }
    ws.connect(url, options).catch((e: BusinessError) => {
      l.onError(`connect ${e.code} ${e.message}`);
    });
    return conn;
  }
}

class OhInflater implements Inflater {
  inflate(data: Uint8Array): Uint8Array {
    return Inflate.zlib(data);
  }
}

class OhTimers implements TimerHost {
  setInterval(fn: () => void, ms: number): number {
    return setInterval(fn, ms);
  }

  clearInterval(id: number): void {
    clearInterval(id);
  }

  setTimeout(fn: () => void, ms: number): number {
    return setTimeout(fn, ms);
  }

  clearTimeout(id: number): void {
    clearTimeout(id);
  }
}

export function installOhPlatform(): void {
  Platform.install(new OhHttp(), new OhWs(), new OhInflater(), new OhTimers());
  Platform.log = (msg: string) => Log.i('core', msg);
}
