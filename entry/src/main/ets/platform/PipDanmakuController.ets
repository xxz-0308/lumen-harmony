import { FrameNode, NodeController, ReactiveBuilderNode, UIContext } from '@kit.ArkUI';
import { DanmakuCanvas, DanmakuEngine } from '../danmaku/DanmakuCanvas';

@ObservedV2
class PipDanmakuState {
  @Trace visible: boolean = false;
  @Trace enabled: boolean = true;
  @Trace styleVersion: number = 0;
  bind: (engine: DanmakuEngine | null) => void;

  constructor(bind: (engine: DanmakuEngine | null) => void) {
    this.bind = bind;
  }
}

@Builder
function pipDanmakuContent(state: PipDanmakuState) {
  Stack() {
    DanmakuCanvas({ visible: state.visible && state.enabled, styleVersion: state.styleVersion,
      bind: (engine: DanmakuEngine | null) => state.bind(engine) })
  }
  .width('100%')
  .height('100%')
  .hitTestBehavior(HitTestMode.None)
}

/** Transparent PiP-local UI: the system still owns the single native video surface. */
export class PipDanmakuController extends NodeController {
  private state: PipDanmakuState;
  private node: ReactiveBuilderNode<[PipDanmakuState]> | null = null;
  private engine: DanmakuEngine | null = null;
  private onEngineBind: (engine: DanmakuEngine | null) => void;
  private disposed: boolean = false;
  private generation: number = 0;

  constructor(onEngineBind: (engine: DanmakuEngine | null) => void) {
    super();
    this.onEngineBind = onEngineBind;
    this.state = new PipDanmakuState((engine: DanmakuEngine | null) => {
      if (this.disposed) { engine?.setActive(false); return; }
      this.engine = engine;
      this.onEngineBind(engine);
    });
  }

  makeNode(context: UIContext): FrameNode | null {
    if (this.disposed) return null;
    const generation = ++this.generation;
    this.engine?.setActive(false);
    this.onEngineBind(null);
    this.node?.dispose();
    const previous = this.state;
    const state = new PipDanmakuState((engine: DanmakuEngine | null) => {
      if (this.disposed || generation !== this.generation) { engine?.setActive(false); return; }
      this.engine = engine;
      this.onEngineBind(engine);
    });
    state.visible = previous.visible;
    state.enabled = previous.enabled;
    state.styleVersion = previous.styleVersion;
    this.state = state;
    const node = new ReactiveBuilderNode<[PipDanmakuState]>(context);
    context.runScopedTask(() => node.build(wrapBuilder(pipDanmakuContent), {}, state));
    this.node = node;
    return node.getFrameNode();
  }

  setVisible(visible: boolean): void { this.state.visible = visible; }
  setEnabled(enabled: boolean): void { this.state.enabled = enabled; }
  setStyleVersion(version: number): void { this.state.styleVersion = version; }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.generation++;
    this.engine?.setActive(false);
    this.onEngineBind(null);
    this.node?.dispose();
    this.node = null;
    this.engine = null;
  }
}
