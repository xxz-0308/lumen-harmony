/** One mounted cover owns one source. Occlusion by its live destination is not scrolling. */
export class HeroSource {
  id: string = '';
  private visible: boolean = false;
  private captured: boolean = false;
  private capturedVisible: boolean = false;
  private bounds: string = '';

  mount(id: string): void {
    this.unmount();
    this.id = id;
    HeroSources.add(this);
  }

  unmount(): void {
    HeroSources.remove(this);
    this.id = '';
    this.visible = false;
    this.captured = false;
    this.capturedVisible = false;
    this.bounds = '';
  }

  setVisible(visible: boolean): void {
    this.visible = visible;
    // Navigation hides the entire source page. Preserve the pre-navigation viewport
    // evidence, but removal, identity changes and layout changes still invalidate it.
  }

  setBounds(bounds: string): void {
    if (this.captured && bounds !== this.bounds) this.capturedVisible = false;
    this.bounds = bounds;
  }

  capture(): void {
    this.captured = true;
    this.capturedVisible = this.visible && this.bounds.length > 0;
  }

  canReturn(): boolean {
    return this.captured && this.capturedVisible;
  }

  release(): void {
    this.captured = false;
    this.capturedVisible = false;
  }
}

export class HeroSources {
  private static sources: Set<HeroSource> = new Set<HeroSource>();

  static add(source: HeroSource): void { HeroSources.sources.add(source); }
  static remove(source: HeroSource): void { HeroSources.sources.delete(source); }

  static canReturn(id: string): boolean {
    if (id.length === 0) return false;
    let matches = 0;
    let valid = false;
    HeroSources.sources.forEach((source: HeroSource) => {
      if (source.id === id) {
        matches++;
        valid = source.canReturn();
      }
    });
    return matches === 1 && valid;
  }

  static release(id: string): void {
    HeroSources.sources.forEach((source: HeroSource) => {
      if (source.id === id) source.release();
    });
  }
}
