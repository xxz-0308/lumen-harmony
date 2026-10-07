/** How far ahead of the picture a bullet may appear: lively, but not seconds early. */
export const BULLET_LEAD_MS = 1000;
const MAX_QUEUED = 600;

class PendingBullet {
  at: number;
  text: string;
  color: number;

  constructor(at: number, text: string, color: number) {
    this.at = at;
    this.text = text;
    this.color = color;
  }
}

/**
 * Holds flying danmaku until the video shows roughly the moment they were sent. Chat arrives in
 * real time while the player runs several seconds behind live, so without this every comment
 * reacts to something the viewer has not seen yet. Release order always follows arrival order.
 */
export class BulletDelay {
  private queue: PendingBullet[] = [];
  private timer: number = -1;
  private lastAt: number = 0;
  private sink: (text: string, color: number) => void;
  private delayOf: () => number;
  private now: () => number;

  constructor(sink: (text: string, color: number) => void, delayOf: () => number,
    now: () => number = () => Date.now()) {
    this.sink = sink;
    this.delayOf = delayOf;
    this.now = now;
  }

  push(text: string, color: number): void {
    const now = this.now();
    const delay = Math.max(0, this.delayOf());
    if (delay <= 0 && this.queue.length === 0) {
      this.sink(text, color);
      return;
    }
    // Never schedule before an earlier message, even when the delay just shrank.
    const at = Math.max(now + delay, this.lastAt);
    this.lastAt = at;
    this.queue.push(new PendingBullet(at, text, color));
    if (this.queue.length > MAX_QUEUED) {
      this.queue.splice(0, this.queue.length - MAX_QUEUED);
    }
    this.schedule();
  }

  clear(): void {
    this.queue = [];
    this.lastAt = 0;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private schedule(): void {
    if (this.timer >= 0 || this.queue.length === 0) {
      return;
    }
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.flush();
    }, Math.max(0, this.queue[0].at - this.now()));
  }

  private flush(): void {
    const now = this.now();
    while (this.queue.length > 0 && this.queue[0].at <= now) {
      const b = this.queue.shift() as PendingBullet;
      this.sink(b.text, b.color);
    }
    this.schedule();
  }
}
