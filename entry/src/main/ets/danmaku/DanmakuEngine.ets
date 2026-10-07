import { displaySync } from '@kit.ArkGraphics2D';
import { Settings } from '../app/Settings';

class Bullet {
  text: string = '';
  color: string = '#FFFFFF';
  width: number = 0;
  x: number = 0;
  lane: number = 0;
  speed: number = 0;
}

/** Converts 0xRRGGBB into a CSS color, softening pure black which is unreadable on video. */
function cssColor(rgb: number): string {
  const c = rgb === 0 ? 0x333333 : rgb;
  return `#${(c & 0xffffff).toString(16).padStart(6, '0')}`;
}

/**
 * Scrolling danmaku renderer. Bullets are laid out in lanes and advanced every vsync
 * (up to the panel's 144Hz) on a single Canvas with bounded live and waiting queues.
 */
export class DanmakuEngine {
  private ctx: CanvasRenderingContext2D;
  private sync: displaySync.DisplaySync | null = null;
  private bullets: Bullet[] = [];
  private queue: Bullet[] = [];
  private laneTail: Bullet[] = [];
  private lastTs: number = 0;
  private w: number = 0;
  private h: number = 0;
  private running: boolean = false;
  private cleared: boolean = true;
  visible: boolean = true;

  constructor(ctx: CanvasRenderingContext2D) {
    this.ctx = ctx;
  }

  resize(w: number, h: number): void {
    if (this.w === w && this.h === h) {
      return;
    }
    const first = this.w <= 0 || this.h <= 0;
    this.w = w;
    this.h = h;
    if (!first) {
      // In-flight bullets carry x/speed computed for the old width; re-anchor them.
      this.clear();
    }
  }

  private get fontSize(): number {
    return Settings.inst.danmakuSize;
  }

  private get laneHeight(): number {
    return Math.round(this.fontSize * 1.45);
  }

  private get laneCount(): number {
    const usable = this.h * Math.max(0.1, Math.min(1, Settings.inst.danmakuArea));
    return Math.max(1, Math.floor((usable - 6) / this.laneHeight));
  }

  /** Seconds a bullet takes to cross the screen at 1x. */
  private get duration(): number {
    const base = 7 + Math.min(5, this.w / 400);
    return base / Math.max(0.3, Settings.inst.danmakuSpeed);
  }

  start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.lastTs = 0;
    const s = displaySync.create();
    s.setExpectedFrameRateRange({ expected: 120, min: 60, max: 144 });
    s.on('frame', (info: displaySync.IntervalInfo) => this.frame(info.timestamp));
    s.start();
    this.sync = s;
  }

  stop(): void {
    this.running = false;
    const s = this.sync;
    this.sync = null;
    if (s !== null) {
      s.stop();
      s.off('frame');
    }
  }

  clear(): void {
    this.bullets.length = 0;
    this.queue.length = 0;
    this.laneTail.length = 0;
    this.ctx.clearRect(0, 0, this.w, this.h);
    this.cleared = true;
  }

  push(text: string, color: number): void {
    if (!this.visible || this.w <= 0) {
      return;
    }
    if (this.bullets.length + this.queue.length >= Settings.inst.danmakuMax) {
      return;
    }
    const b = new Bullet();
    b.text = text.length > 40 ? text.substring(0, 40) + '…' : text;
    b.color = Settings.inst.danmakuKeepColor ? cssColor(color) : '#FFFFFF';
    this.ctx.font = `bold ${this.fontSize}vp sans-serif`;
    b.width = this.ctx.measureText(b.text).width;
    b.x = this.w;
    b.speed = (this.w + b.width) / this.duration;
    if (!this.running) {
      this.start();
    }
    if (!this.place(b)) {
      if (this.queue.length < 30) {
        this.queue.push(b);
      }
    }
  }

  /** Finds a lane where the bullet will neither overlap nor catch up with the previous one. */
  private place(b: Bullet): boolean {
    const lanes = this.laneCount;
    for (let i = 0; i < lanes; i++) {
      const tail = this.laneTail[i];
      if (tail === undefined || this.bullets.indexOf(tail) < 0) {
        this.assign(b, i);
        return true;
      }
      const tailEnd = tail.x + tail.width;
      if (tailEnd + 24 > this.w) {
        continue;
      }
      const tailExit = tailEnd / tail.speed;
      const headReach = this.w / b.speed;
      if (headReach >= tailExit) {
        this.assign(b, i);
        return true;
      }
    }
    return false;
  }

  private assign(b: Bullet, lane: number): void {
    b.lane = lane;
    b.x = this.w;
    this.laneTail[lane] = b;
    this.bullets.push(b);
  }

  /** Drops bullets that no longer fit the configured area or exceed the current cap. */
  trim(): void {
    const lanes = this.laneCount;
    if (Settings.inst.danmakuMax < this.bullets.length) {
      this.bullets = this.bullets.slice(0, Settings.inst.danmakuMax);
    }
    this.bullets = this.bullets.filter((b: Bullet) => b.lane < lanes);
    this.queue = [];
    this.laneTail = [];
  }

  private frame(tsNs: number): void {
    if (!this.running) {
      return;
    }
    const dt = this.lastTs === 0 ? 0 : Math.min(0.05, (tsNs - this.lastTs) / 1e9);
    this.lastTs = tsNs;
    if (this.bullets.length === 0 && this.queue.length === 0) {
      if (!this.cleared) {
        this.ctx.clearRect(0, 0, this.w, this.h);
        this.cleared = true;
      }
      // Nothing to animate: park the display sync until the next bullet arrives.
      this.stop();
      return;
    }
    if (this.queue.length > 0) {
      // Keep the original order and placement timing without allocating a waiting array per frame.
      let waiting = 0;
      const count = this.queue.length;
      for (let i = 0; i < count; i++) {
        const b = this.queue[i];
        if (!this.place(b) && waiting < 30) {
          this.queue[waiting++] = b;
        }
      }
      this.queue.length = waiting;
    }
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    this.cleared = false;
    if (!this.visible) {
      return;
    }
    const size = this.fontSize;
    const lh = this.laneHeight;
    const stroke = Settings.inst.danmakuStroke;
    ctx.font = `bold ${size}vp sans-serif`;
    ctx.textBaseline = 'middle';
    ctx.globalAlpha = Settings.inst.danmakuOpacity;
    ctx.lineJoin = 'round';
    if (stroke === 'stroke') {
      ctx.lineWidth = Math.max(2, size / 8);
      ctx.strokeStyle = 'rgba(0,0,0,0.72)';
      ctx.shadowBlur = 0;
    } else if (stroke === 'shadow') {
      ctx.shadowColor = 'rgba(0,0,0,0.85)';
      ctx.shadowBlur = 4;
      ctx.shadowOffsetX = 0;
      ctx.shadowOffsetY = 1;
    } else {
      ctx.shadowBlur = 0;
    }
    let alive = 0;
    const count = this.bullets.length;
    for (let i = 0; i < count; i++) {
      const b = this.bullets[i];
      b.x -= b.speed * dt;
      if (b.x + b.width < 0) {
        continue;
      }
      this.bullets[alive++] = b;
      const y = 4 + b.lane * lh + lh / 2;
      if (stroke === 'stroke') {
        ctx.strokeText(b.text, b.x, y);
      }
      ctx.fillStyle = b.color;
      ctx.fillText(b.text, b.x, y);
    }
    this.bullets.length = alive;
    ctx.globalAlpha = 1;
    ctx.shadowBlur = 0;
  }
}

