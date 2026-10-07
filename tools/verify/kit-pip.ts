export class FakePipController {
  listeners = new Map<string, (value: any) => void>();
  autoStart = false;
  status = -1;
  size = [0, 0];
  stops = 0;
  finishStart: (() => void) | null = null;

  on(event: string, callback: (value: any) => void): void { this.listeners.set(event, callback); }
  off(event: string): void { this.listeners.delete(event); }
  emit(event: string, value: any): void { this.listeners.get(event)?.(value); }
  setAutoStartEnabled(value: boolean): void { this.autoStart = value; }
  updatePiPControlStatus(_type: number, status: number): void { this.status = status; }
  updateContentSize(width: number, height: number): void { this.size = [width, height]; }
  startPiP(): Promise<void> {
    return new Promise((resolve) => {
      this.finishStart = () => {
        this.emit('stateChange', 2);
        resolve();
      };
    });
  }
  async stopPiP(): Promise<void> { this.stops++; }
}

export const creations: { config: any; resolve: (controller: FakePipController) => void }[] = [];
export const PiPWindow = {
  isPiPEnabled: () => true,
  PiPTemplateType: { VIDEO_LIVE: 3 },
  VideoLiveControlGroup: { VIDEO_PLAY_PAUSE: 401 },
  PiPControlType: { VIDEO_PLAY_PAUSE: 0 },
  PiPControlStatus: { PLAY: 1, PAUSE: 0 },
  PiPState: { ABOUT_TO_START: 1, STARTED: 2, ABOUT_TO_STOP: 3, STOPPED: 4, ABOUT_TO_RESTORE: 5, ERROR: 6 },
  create: (config: any): Promise<FakePipController> => new Promise((resolve) => {
    creations.push({ config, resolve });
  })
};
