// Node implementations of the protocol-layer transports, used only for verification.
import WebSocket from 'ws';
import {
  HttpRequest, HttpResponse, HttpTransport, Inflater, Platform, TimerHost, WsConnection, WsListener, WsTransport
} from '../../entry/src/main/ets/core/common/Transport';
import { Inflate } from '../../entry/src/main/ets/core/common/Inflate';

class NodeHttp implements HttpTransport {
  async send(req: HttpRequest): Promise<HttpResponse> {
    const init: RequestInit = { method: req.method, headers: req.headers, redirect: 'follow' };
    if (req.bodyBytes) {
      init.body = req.bodyBytes;
    } else if (req.body !== undefined) {
      init.body = req.body;
    }
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), req.timeoutMs);
    init.signal = ctrl.signal;
    try {
      const r = await fetch(req.url, init);
      const res = new HttpResponse();
      res.status = r.status;
      const buf = new Uint8Array(await r.arrayBuffer());
      if (req.binary) {
        res.bytes = buf;
      } else {
        res.text = new TextDecoder().decode(buf);
      }
      r.headers.forEach((v, k) => { res.headers[k] = v; });
      res.setCookies = r.headers.getSetCookie();
      return res;
    } finally {
      clearTimeout(timer);
    }
  }
}

class NodeWs implements WsTransport {
  connect(url: string, headers: Record<string, string>, l: WsListener): WsConnection {
    const ws = new WebSocket(url, { headers });
    ws.binaryType = 'nodebuffer';
    ws.on('open', () => l.onOpen());
    ws.on('message', (data: Buffer, isBinary: boolean) => {
      if (isBinary) {
        l.onBinary(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
      } else {
        l.onText(data.toString('utf8'));
      }
    });
    ws.on('close', (code: number, reason: Buffer) => l.onClose(`${code} ${reason}`));
    ws.on('error', (e: Error) => l.onError(String(e)));
    return {
      sendBinary: (d: Uint8Array) => { if (ws.readyState === WebSocket.OPEN) ws.send(d); },
      sendText: (t: string) => { if (ws.readyState === WebSocket.OPEN) ws.send(t); },
      close: () => ws.close(),
    };
  }
}

class NodeInflater implements Inflater {
  inflate(data: Uint8Array): Uint8Array {
    return Inflate.zlib(data);
  }
}

class NodeTimers implements TimerHost {
  setInterval(fn: () => void, ms: number): number { return setInterval(fn, ms) as unknown as number; }
  clearInterval(id: number): void { clearInterval(id as unknown as NodeJS.Timeout); }
  setTimeout(fn: () => void, ms: number): number { return setTimeout(fn, ms) as unknown as number; }
  clearTimeout(id: number): void { clearTimeout(id as unknown as NodeJS.Timeout); }
}

export function installNodePlatform(): void {
  Platform.install(new NodeHttp(), new NodeWs(), new NodeInflater(), new NodeTimers());
  Platform.log = () => {};
}
