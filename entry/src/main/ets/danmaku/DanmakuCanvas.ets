import { DanmakuEngine } from './DanmakuEngine';

export { DanmakuEngine } from './DanmakuEngine';

/** Canvas host for the engine. The owner feeds text via the `bind` callback. */
@ComponentV2
export struct DanmakuCanvas {
  @Param visible: boolean = true;
  @Param styleVersion: number = 0;
  @Event bind: (engine: DanmakuEngine | null) => void = () => {
  };
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private engine: DanmakuEngine = new DanmakuEngine(this.ctx);
  private ready: boolean = false;

  aboutToAppear(): void {
    if (this.ready) this.bind(this.engine);
  }

  @Monitor('visible')
  onVisible(): void {
    this.engine.visible = this.visible;
    if (!this.visible) {
      this.engine.clear();
      this.engine.stop();
    } else if (this.ready) {
      this.bind(this.engine);
    }
  }

  /** The settings panel explicitly invalidates in-flight bullet geometry. */
  @Monitor('styleVersion')
  onStyleChange(): void {
    this.engine.clear();
  }

  aboutToDisappear(): void {
    this.engine.stop();
    this.bind(null);
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.ready = true;
        const context = this.getUIContext();
        this.engine.setScope((task: () => void) => context.runScopedTask(task));
        this.engine.visible = this.visible;
        this.engine.resize(this.ctx.width, this.ctx.height);
        if (this.visible) this.engine.start();
        this.bind(this.engine);
      })
      .onAreaChange((o: Area, n: Area) => {
        this.engine.resize(n.width as number, n.height as number);
      })
  }
}
