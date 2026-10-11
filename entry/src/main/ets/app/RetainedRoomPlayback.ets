/** One SDK-cached room may keep playing after a confirmed manual PiP handoff. */
export class RetainedRoomPlayback {
  private static nextOwner: number = 0;
  private static owner: number = 0;
  private static closePlayback: (() => void) | null = null;

  static newOwner(): number {
    return ++RetainedRoomPlayback.nextOwner;
  }

  static retain(owner: number, close: () => void): void {
    RetainedRoomPlayback.close();
    RetainedRoomPlayback.owner = owner;
    RetainedRoomPlayback.closePlayback = close;
  }

  /** Restoring the cached destination transfers presentation back; it does not close playback. */
  static release(owner: number): void {
    if (owner !== RetainedRoomPlayback.owner) return;
    RetainedRoomPlayback.owner = 0;
    RetainedRoomPlayback.closePlayback = null;
  }

  static close(): void {
    const close = RetainedRoomPlayback.closePlayback;
    RetainedRoomPlayback.owner = 0;
    RetainedRoomPlayback.closePlayback = null;
    close?.();
  }
}
