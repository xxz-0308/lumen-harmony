import { FrameCallback, UIContext } from '@kit.ArkUI';

class RoomMountStep extends FrameCallback {
  private publish: () => void;

  constructor(publish: () => void) {
    super();
    this.publish = publish;
  }

  onIdle(timeLeftInNano: number): void {
    this.publish();
  }
}

/** Build room layers on separate idle frames, not in one navigation-mount/layout burst. */
export class RoomMount {
  private epoch: number = 0;

  start(context: UIContext, publish: (stage: number) => void): void {
    const epoch = ++this.epoch;
    const next = (stage: number): void => {
      context.postFrameCallback(new RoomMountStep(() => {
        if (epoch !== this.epoch) return;
        publish(stage);
        if (stage < 5 && epoch === this.epoch) next(stage + 1);
      }));
    };
    next(0);
  }

  cancel(): void {
    this.epoch++;
  }

  /** Keep resources alive through the frame which removes their last visible Image node. */
  static afterPaint(context: UIContext, work: () => void): void {
    context.postFrameCallback(new RoomMountStep(work));
  }
}
