import { PiPWindow } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Log } from '../util/Log';

export interface PipHandlers {
  play: () => void;
  pause: () => void;
  /** PiP started or stopped; `restoring` is true when the user tapped back into the app. */
  onActive: (active: boolean, restoring: boolean) => void;
}

/**
 * Live picture-in-picture around the room's XComponent. The same surface keeps rendering in the
 * floating window, so no second player is needed. Auto start is only armed while playing with the
 * "画中画" leave behaviour, which makes the home gesture shrink the video into a PiP window.
 */
export class LivePip {
  private controller: PiPWindow.PiPController | null = null;
  private creating: boolean = false;
  private generation: number = 0;
  private xc: XComponentController | null = null;
  private handlers: PipHandlers;
  private autoStart: boolean = false;
  private playing: boolean = false;
  private width: number = 16;
  private height: number = 9;
  private disposed: boolean = false;
  private restoring: boolean = false;
  active: boolean = false;

  constructor(handlers: PipHandlers) {
    this.handlers = handlers;
  }

  static supported(): boolean {
    try {
      return PiPWindow.isPiPEnabled();
    } catch (e) {
      return false;
    }
  }

  /** Called whenever the video XComponent (re)loads; a new controller replaces a stale one. */
  attach(context: common.UIAbilityContext | null, xc: XComponentController, navigationId: string): void {
    if (this.disposed || context === null || !LivePip.supported()) {
      return;
    }
    if (this.xc === xc && (this.controller !== null || this.creating)) {
      return;
    }
    this.release();
    const generation = this.generation;
    this.xc = xc;
    this.creating = true;
    const config: PiPWindow.PiPConfiguration = {
      context: context,
      componentController: xc,
      navigationId: navigationId,
      templateType: PiPWindow.PiPTemplateType.VIDEO_LIVE,
      controlGroups: [PiPWindow.VideoLiveControlGroup.VIDEO_PLAY_PAUSE],
      contentWidth: this.width,
      contentHeight: this.height
    };
    PiPWindow.create(config).then((c: PiPWindow.PiPController) => {
      if (this.disposed || generation !== this.generation || this.xc !== xc) {
        c.stopPiP().catch(() => {});
        return;
      }
      this.creating = false;
      this.controller = c;
      c.on('stateChange', (state: PiPWindow.PiPState) => {
        if (generation === this.generation) {
          this.onState(state);
        }
      });
      c.on('controlEvent', (e: PiPWindow.ControlEventParam) => {
        if (generation !== this.generation || e.controlType !== PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
          return;
        }
        if (e.status === PiPWindow.PiPControlStatus.PLAY) {
          this.handlers.play();
        } else if (e.status === PiPWindow.PiPControlStatus.PAUSE) {
          this.handlers.pause();
        }
      });
      // The first decoded frame can change the size while create() is pending.
      try {
        c.updateContentSize(this.width, this.height);
      } catch (e) {
        Log.w('pip', 'initial content size update failed');
      }
      this.applyAutoStart();
      this.applyPlaying();
    }).catch((e: Error) => {
      if (generation === this.generation) {
        this.creating = false;
        Log.w('pip', `create failed: ${e.message ?? ''}`);
      }
    });
  }

  private onState(state: PiPWindow.PiPState): void {
    if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
      this.restoring = true;
    } else if (state === PiPWindow.PiPState.ABOUT_TO_START) {
      this.restoring = false;
    }
    const active = state === PiPWindow.PiPState.ABOUT_TO_START || state === PiPWindow.PiPState.STARTED;
    if (active !== this.active) {
      this.active = active;
      this.handlers.onActive(active, this.restoring);
    }
    if (state === PiPWindow.PiPState.ERROR) {
      Log.w('pip', 'PiP window error');
    }
  }

  setAutoStart(enabled: boolean): void {
    this.autoStart = enabled;
    this.applyAutoStart();
  }

  setPlaying(playing: boolean): void {
    this.playing = playing;
    this.applyPlaying();
  }

  setContentSize(width: number, height: number): void {
    if (width <= 0 || height <= 0 || (width === this.width && height === this.height)) {
      return;
    }
    this.width = width;
    this.height = height;
    try {
      this.controller?.updateContentSize(width, height);
    } catch (e) {
      // not started yet; the size is used on the next create
    }
  }

  async start(): Promise<void> {
    const c = this.controller;
    if (c === null) {
      throw new Error('画中画暂不可用');
    }
    const generation = this.generation;
    await c.startPiP();
    // Leaving the room or replacing its surface can race the native start promise.
    if (this.disposed || generation !== this.generation || this.controller !== c) {
      await c.stopPiP().catch((e: Error) => Log.w('pip', `stale start cleanup failed: ${e.message ?? ''}`));
    }
  }

  private applyAutoStart(): void {
    try {
      this.controller?.setAutoStartEnabled(this.autoStart);
    } catch (e) {
      Log.w('pip', 'setAutoStartEnabled failed');
    }
  }

  private applyPlaying(): void {
    try {
      this.controller?.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        this.playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE);
    } catch (e) {
      // only valid once the controller exists
    }
  }

  private release(): void {
    this.generation++;
    this.creating = false;
    const c = this.controller;
    this.controller = null;
    this.xc = null;
    const wasActive = this.active;
    this.active = false;
    this.restoring = false;
    if (c === null) {
      if (wasActive && !this.disposed) {
        this.handlers.onActive(false, false);
      }
      return;
    }
    try {
      c.setAutoStartEnabled(false);
      c.off('stateChange');
      c.off('controlEvent');
    } catch (e) {
      Log.w('pip', 'controller cleanup failed');
    }
    if (wasActive) {
      if (!this.disposed) {
        this.handlers.onActive(false, false);
      }
      c.stopPiP().catch((e: Error) => Log.w('pip', `stop failed: ${e.message ?? ''}`));
    }
  }

  dispose(): void {
    this.disposed = true;
    this.release();
  }
}
