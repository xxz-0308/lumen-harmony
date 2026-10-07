import { HttpRequest, HttpResponse, Platform } from './Transport';
import { JNode } from './Json';

export const UA_PC =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';
export const UA_MOBILE =
  'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';

export class HttpError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export class Query {
  static encode(params: Record<string, string>): string {
    const parts: string[] = [];
    const keys = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      parts.push(`${encodeURIComponent(keys[i])}=${encodeURIComponent(params[keys[i]])}`);
    }
    return parts.join('&');
  }

  static append(url: string, params: Record<string, string>): string {
    const q = Query.encode(params);
    if (q.length === 0) {
      return url;
    }
    return url + (url.indexOf('?') >= 0 ? '&' : '?') + q;
  }

  /** Parses `a=1&b=2` into a record; values are URI-decoded. */
  static parse(query: string): Record<string, string> {
    const out: Record<string, string> = {};
    const q = query.startsWith('?') ? query.substring(1) : query;
    const parts = q.split('&');
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (p.length === 0) {
        continue;
      }
      const eq = p.indexOf('=');
      const k = eq >= 0 ? p.substring(0, eq) : p;
      const v = eq >= 0 ? p.substring(eq + 1) : '';
      out[Query.safeDecode(k)] = Query.safeDecode(v.replace(/\+/g, ' '));
    }
    return out;
  }

  static safeDecode(s: string): string {
    try {
      return decodeURIComponent(s);
    } catch (e) {
      return s;
    }
  }
}

function mergeHeaders(base: Record<string, string>, extra?: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  const bk = Object.keys(base);
  for (let i = 0; i < bk.length; i++) {
    out[bk[i]] = base[bk[i]];
  }
  if (extra) {
    const ek = Object.keys(extra);
    for (let i = 0; i < ek.length; i++) {
      out[ek[i]] = extra[ek[i]];
    }
  }
  return out;
}

/** Thin convenience wrapper over the injected transport. */
export class Http {
  static async send(req: HttpRequest): Promise<HttpResponse> {
    const res = await Platform.http.send(req);
    if (res.status < 200 || res.status >= 400) {
      throw new HttpError(res.status, `HTTP ${res.status} ${req.method} ${req.url.split('?')[0]}`);
    }
    return res;
  }

  static async getText(url: string, query?: Record<string, string>, headers?: Record<string, string>): Promise<string> {
    const req = new HttpRequest();
    req.url = query ? Query.append(url, query) : url;
    req.headers = mergeHeaders({ 'user-agent': UA_PC }, headers);
    const res = await Http.send(req);
    return res.text;
  }

  static async getJson(url: string, query?: Record<string, string>, headers?: Record<string, string>): Promise<JNode> {
    return Http.parseJson(await Http.getText(url, query, headers));
  }

  private static parseJson(text: string): JNode {
    try {
      return JNode.parse(text);
    } catch (e) {
      throw new Error('服务返回了异常数据，请稍后重试');
    }
  }

  static async getResponse(url: string, query?: Record<string, string>,
    headers?: Record<string, string>): Promise<HttpResponse> {
    const req = new HttpRequest();
    req.url = query ? Query.append(url, query) : url;
    req.headers = mergeHeaders({ 'user-agent': UA_PC }, headers);
    return Http.send(req);
  }

  static async postForm(url: string, form: Record<string, string> | string,
    headers?: Record<string, string>): Promise<JNode> {
    const req = new HttpRequest();
    req.url = url;
    req.method = 'POST';
    req.headers = mergeHeaders({
      'user-agent': UA_PC,
      'content-type': 'application/x-www-form-urlencoded'
    }, headers);
    req.body = typeof form === 'string' ? form as string : Query.encode(form as Record<string, string>);
    const res = await Http.send(req);
    return Http.parseJson(res.text);
  }

  static async postJson(url: string, body: string, headers?: Record<string, string>): Promise<JNode> {
    const req = new HttpRequest();
    req.url = url;
    req.method = 'POST';
    req.headers = mergeHeaders({ 'user-agent': UA_PC, 'content-type': 'application/json' }, headers);
    req.body = body;
    const res = await Http.send(req);
    return Http.parseJson(res.text);
  }

  static async postBytes(url: string, body: Uint8Array, headers?: Record<string, string>): Promise<Uint8Array> {
    const req = new HttpRequest();
    req.url = url;
    req.method = 'POST';
    req.headers = mergeHeaders({ 'user-agent': UA_PC }, headers);
    req.bodyBytes = body;
    req.binary = true;
    const res = await Http.send(req);
    return res.bytes;
  }
}

export function stripTags(s: string): string {
  return htmlUnescape(s.replace(/<[^>]*>/g, ''));
}

export function htmlUnescape(s: string): string {
  return s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, '\'').replace(/&#x27;/g, '\'');
}

export function httpsUrl(u: string): string {
  if (u.startsWith('//')) {
    return 'https:' + u;
  }
  if (u.startsWith('http://')) {
    return 'https://' + u.substring(7);
  }
  return u;
}
