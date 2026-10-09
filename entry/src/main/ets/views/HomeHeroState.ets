import { LiveRoomItem } from '../core/model/Models';

@ObservedV2
export class HeroSlideState {
  @Trace item: LiveRoomItem;
  @Trace opacity: number = 1;
  @Trace shift: number = 0;

  constructor(item: LiveRoomItem) {
    this.item = item;
  }
}

/** The single home carousel owns its items and rejects callbacks from an older source. */
@ObservedV2
export class HomeHeroState {
  @Trace slides: HeroSlideState[] = [];
  @Trace index: number = 0;
  @Trace touched: boolean = false;
  @Trace fromFollows: boolean = false;
  @Trace generation: number = 0;
  private active: boolean = false;
  private pending: LiveRoomItem[] = [];
  private pendingFollows: boolean = false;

  static key(item: LiveRoomItem): string {
    return `${item.siteId}_${item.roomId}`;
  }

  static fallback(sources: LiveRoomItem[][]): LiveRoomItem[] {
    const result: LiveRoomItem[] = [];
    const seen: Set<string> = new Set<string>();
    const rows = sources.reduce((n: number, items: LiveRoomItem[]) => Math.max(n, items.length), 0);
    for (let row = 0; row < rows && result.length < 6; row++) {
      for (const items of sources) {
        if (row >= items.length || result.length >= 6) continue;
        const item = items[row];
        const key = HomeHeroState.key(item);
        if (item.roomId.length > 0 && !seen.has(key)) {
          seen.add(key);
          result.push(item);
        }
      }
    }
    return result;
  }

  update(items: LiveRoomItem[], follows: boolean): void {
    this.pending = items;
    this.pendingFollows = follows;
    if (!this.touched) this.reconcile();
  }

  setActive(active: boolean): void {
    if (this.active === active) return;
    this.active = active;
    this.generation++;
    this.resetStyles();
    if (!active) this.endTouch();
  }

  beginTouch(): void {
    if (this.active) this.touched = true;
  }

  endTouch(): void {
    this.touched = false;
    this.reconcile();
  }

  select(index: number, generation: number): void {
    if (!this.accepts(index, generation)) return;
    this.index = index;
  }

  transition(index: number, position: number, generation: number): void {
    if (!this.accepts(index, generation)) return;
    const p = Math.max(-1, Math.min(1, position));
    this.slides[index].opacity = 1 - Math.abs(p) * 0.7;
    this.slides[index].shift = p;
  }

  finish(index: number, generation: number): void {
    if (!this.accepts(index, generation)) return;
    this.index = index;
    // No timed-out proxy may leave the selected slide dimmed or shifted at rest.
    this.generation++;
    this.resetStyles();
  }

  private accepts(index: number, generation: number): boolean {
    return this.active && generation === this.generation && index >= 0 && index < this.slides.length;
  }

  private resetStyles(): void {
    for (const slide of this.slides) {
      slide.opacity = 1;
      slide.shift = 0;
    }
  }

  private reconcile(): void {
    const current = this.slides[this.index];
    const currentKey = current === undefined ? '' : HomeHeroState.key(current.item);
    const keys = this.pending.map((item: LiveRoomItem) => HomeHeroState.key(item));
    const previous = this.slides.map((slide: HeroSlideState) => HomeHeroState.key(slide.item));
    const changed = keys.join('|') !== previous.join('|');
    const old: Map<string, HeroSlideState> = new Map<string, HeroSlideState>();
    for (const slide of this.slides) old.set(HomeHeroState.key(slide.item), slide);
    if (changed) {
      this.slides = this.pending.map((item: LiveRoomItem) => {
        const slide = old.get(HomeHeroState.key(item)) ?? new HeroSlideState(item);
        slide.item = item;
        return slide;
      });
    } else {
      for (let i = 0; i < this.pending.length; i++) this.slides[i].item = this.pending[i];
    }
    this.fromFollows = this.pendingFollows;
    if (changed) {
      this.generation++;
      const keep = keys.indexOf(currentKey);
      this.index = keep >= 0 ? keep : 0;
      this.resetStyles();
    } else if (this.index >= this.slides.length) {
      this.index = 0;
    }
  }
}
