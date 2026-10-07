/**
 * Network abstractions injected into the protocol layer.
 * HarmonyOS implementations live in `platform/`; Node implementations in `tools/verify/`.
 */

export class HttpRequest {
  url: string = '';
  method: string = 'GET';
  headers: Record<string, string> = {};
  /** Text body (form or JSON). */
  body?: string;
  /** Binary body (takes precedence over `body`). */
  bodyBytes?: Uint8Array;
  /** When true the response is delivered as bytes in `HttpResponse.bytes`. */
  binary: boolean = false;
  timeoutMs: number = 15000;
}

export class HttpResponse {
  status: number = 0;
  text: string = '';
  bytes: Uint8Array = new Uint8Array(0);
  headers: Record<string, string> = {};
  /** Raw Set-Cookie fields; never forward these as a Cookie request header. */
  setCookies: string[] = [];
}

export interface HttpTransport {
  send(req: HttpRequest): Promise<HttpResponse>;
}

export interface WsListener {
  onOpen: () => void;
  onBinary: (data: Uint8Array) => void;
  onText: (text: string) => void;
  onClose: (reason: string) => void;
  onError: (err: string) => void;
}

export interface WsConnection {
  sendBinary(data: Uint8Array): void;
  sendText(text: string): void;
  close(): void;
}

export interface WsTransport {
  connect(url: string, headers: Record<string, string>, listener: WsListener): WsConnection;
}

export interface Inflater {
  /** zlib (RFC 1950) inflate. */
  inflate(data: Uint8Array): Uint8Array;
}

/** Timer indirection so danmaku heartbeats work identically in Node and ArkTS. */
export interface TimerHost {
  setInterval(fn: () => void, ms: number): number;
  clearInterval(id: number): void;
  setTimeout(fn: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

export class Platform {
  static http: HttpTransport;
  static ws: WsTransport;
  static inflater: Inflater;
  static timers: TimerHost;
  static log: (msg: string) => void = (msg: string) => {
    console.info(msg);
  };

  static install(http: HttpTransport, ws: WsTransport, inflater: Inflater, timers: TimerHost): void {
    Platform.http = http;
    Platform.ws = ws;
    Platform.inflater = inflater;
    Platform.timers = timers;
  }
}
