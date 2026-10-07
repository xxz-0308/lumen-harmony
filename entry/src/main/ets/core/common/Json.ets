/**
 * Defensive accessor for loosely-typed JSON from scraped endpoints.
 * Every lookup returns a JNode, so a missing field yields a default instead of a crash.
 */
export class JNode {
  readonly value: Object | null | undefined;

  constructor(value: Object | null | undefined) {
    this.value = value;
  }

  static parse(text: string): JNode {
    return new JNode(JSON.parse(text) as Object);
  }

  static tryParse(text: string): JNode {
    try {
      return JNode.parse(text);
    } catch (e) {
      return new JNode(undefined);
    }
  }

  get exists(): boolean {
    return this.value !== undefined && this.value !== null;
  }

  get isArray(): boolean {
    return Array.isArray(this.value);
  }

  get isObject(): boolean {
    return this.exists && typeof this.value === 'object' && !Array.isArray(this.value);
  }

  get(key: string): JNode {
    if (this.isObject) {
      const rec = this.value as Record<string, Object>;
      return new JNode(rec[key]);
    }
    return new JNode(undefined);
  }

  /** Walks a dotted path; numeric segments index into arrays, e.g. "data.list.0.name". */
  path(dotted: string): JNode {
    let node: JNode = this;
    const parts = dotted.split('.');
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (node.isArray && /^\d+$/.test(p)) {
        node = node.at(Number(p));
      } else {
        node = node.get(p);
      }
    }
    return node;
  }

  at(index: number): JNode {
    if (this.isArray) {
      const arr = this.value as Object[];
      return new JNode(index >= 0 && index < arr.length ? arr[index] : undefined);
    }
    return new JNode(undefined);
  }

  list(): JNode[] {
    if (!this.isArray) {
      return [];
    }
    const arr = this.value as Object[];
    const out: JNode[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(new JNode(arr[i]));
    }
    return out;
  }

  keys(): string[] {
    if (!this.isObject) {
      return [];
    }
    return Object.keys(this.value as Record<string, Object>);
  }

  get length(): number {
    return this.isArray ? (this.value as Object[]).length : 0;
  }

  str(def: string = ''): string {
    const v = this.value;
    if (v === undefined || v === null) {
      return def;
    }
    if (typeof v === 'string') {
      return v as string;
    }
    if (typeof v === 'number' || typeof v === 'boolean') {
      return String(v);
    }
    return JSON.stringify(v);
  }

  num(def: number = 0): number {
    const v = this.value;
    if (typeof v === 'number') {
      return v as number;
    }
    if (typeof v === 'string') {
      const n = Number((v as string).trim());
      return (v as string).trim().length > 0 && !isNaN(n) ? n : def;
    }
    if (typeof v === 'boolean') {
      return (v as boolean) ? 1 : 0;
    }
    return def;
  }

  int(def: number = 0): number {
    return Math.trunc(this.num(def));
  }

  bool(def: boolean = false): boolean {
    const v = this.value;
    if (typeof v === 'boolean') {
      return v as boolean;
    }
    if (typeof v === 'number') {
      return (v as number) !== 0;
    }
    if (typeof v === 'string') {
      const s = (v as string).toLowerCase();
      return s === 'true' || s === '1';
    }
    return def;
  }
}
