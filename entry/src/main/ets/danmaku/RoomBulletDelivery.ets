import { BulletDelay, BULLET_LEAD_MS } from './BulletDelay';

export interface BulletRenderer {
  pushScoped(text: string, color: number): void;
  setActive(active: boolean): void;
}

/** One room stream and deadline queue, with only one visible rendering destination. */
export class RoomBulletDelivery {
  private main: BulletRenderer | null = null;
  private pip: BulletRenderer | null = null;
  private target: BulletRenderer | null = null;
  private mainActive: boolean = false;
  private pipActive: boolean = false;
  private enabled: boolean = true;
  private disposed: boolean = false;
  private delay: BulletDelay;

  constructor(latencyOf: () => number) {
    this.delay = new BulletDelay((text: string, color: number) => this.target?.pushScoped(text, color),
      () => latencyOf() - BULLET_LEAD_MS);
    this.delay.setReady(false);
  }

  bindMain(engine: BulletRenderer | null): void {
    if (this.disposed) { engine?.setActive(false); return; }
    if (this.main !== engine) this.main?.setActive(false);
    this.main = engine;
    this.updateTarget();
  }

  bindPip(engine: BulletRenderer | null): void {
    if (this.disposed) { engine?.setActive(false); return; }
    if (this.pip !== engine) this.pip?.setActive(false);
    this.pip = engine;
    this.updateTarget();
  }

  setPresentation(mainActive: boolean, pipActive: boolean, enabled: boolean): void {
    if (this.disposed) return;
    if (this.enabled && !enabled) this.delay.clear();
    this.mainActive = mainActive;
    this.pipActive = pipActive;
    this.enabled = enabled;
    this.updateTarget();
  }

  private updateTarget(): void {
    const main = this.enabled && this.mainActive && !this.pipActive;
    const pip = this.enabled && this.pipActive;
    this.main?.setActive(main);
    this.pip?.setActive(pip);
    this.target = pip ? this.pip : (main ? this.main : null);
    this.delay.setReady(this.target !== null);
  }

  push(text: string, color: number): void {
    if (!this.disposed && this.enabled && (this.mainActive || this.pipActive)) this.delay.push(text, color);
  }

  clear(): void {
    this.delay.clear();
    this.main?.setActive(false);
    this.pip?.setActive(false);
    this.updateTarget();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.delay.clear();
    this.main?.setActive(false);
    this.pip?.setActive(false);
    this.main = null;
    this.pip = null;
    this.target = null;
  }
}
