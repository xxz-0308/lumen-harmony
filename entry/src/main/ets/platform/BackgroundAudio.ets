import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { Log } from '../util/Log';

export interface MediaControls {
  play: () => void;
  pause: () => void;
}

/**
 * Background audio for the live room. The system only keeps AVPlayer audible in the
 * background when the app owns an active AVSession AND a continuous AUDIO_PLAYBACK task.
 * The task is only requested while the user chose "后台播放" and a stream is playing,
 * and it has to be requested while the app is still in the foreground.
 */
export class BackgroundAudio {
  private static context: common.UIAbilityContext | null = null;
  private static session: avSession.AVSession | null = null;
  private static creating: Promise<avSession.AVSession | null> | null = null;
  private static controls: MediaControls | null = null;
  private static title: string = '';
  private static artist: string = '';
  private static playing: boolean = false;
  /** Whether the continuous task should exist right now. */
  private static wantTask: boolean = false;
  private static taskStarted: boolean = false;
  private static taskBusy: boolean = false;
  private static gen: number = 0;

  static attach(context: common.UIAbilityContext | null, controls: MediaControls): number {
    const owner = ++BackgroundAudio.gen;
    BackgroundAudio.context = context;
    BackgroundAudio.controls = controls;
    BackgroundAudio.playing = false;
    return owner;
  }

  static setMetadata(title: string, artist: string, owner: number): void {
    if (owner !== BackgroundAudio.gen || BackgroundAudio.controls === null) {
      return;
    }
    if (BackgroundAudio.title === title && BackgroundAudio.artist === artist) {
      return;
    }
    BackgroundAudio.title = title;
    BackgroundAudio.artist = artist;
    const s = BackgroundAudio.session;
    if (s !== null) {
      BackgroundAudio.pushMetadata(s);
    }
  }

  /**
   * @param playing the stream is meant to be playing (shown in the system media card)
   * @param keepTask the room is live and not stopped, even if momentarily loading or paused
   * @param allowBackground the user chose to keep playing when leaving the app
   */
  static update(playing: boolean, keepTask: boolean, allowBackground: boolean, owner: number): void {
    if (owner !== BackgroundAudio.gen || BackgroundAudio.controls === null) {
      return;
    }
    BackgroundAudio.playing = playing;
    BackgroundAudio.wantTask = keepTask && allowBackground;
    if (allowBackground) {
      BackgroundAudio.ensureSession().then((s: avSession.AVSession | null) => {
        if (s !== null) {
          BackgroundAudio.pushState(s);
        }
      });
    }
    BackgroundAudio.syncTask();
  }

  static detach(owner: number): void {
    if (owner !== BackgroundAudio.gen || BackgroundAudio.controls === null) {
      return;
    }
    BackgroundAudio.gen++;
    BackgroundAudio.controls = null;
    BackgroundAudio.playing = false;
    BackgroundAudio.wantTask = false;
    BackgroundAudio.title = '';
    BackgroundAudio.artist = '';
    BackgroundAudio.syncTask();
    const s = BackgroundAudio.session;
    BackgroundAudio.session = null;
    if (s !== null) {
      BackgroundAudio.destroySession(s);
    }
  }

  private static ensureSession(): Promise<avSession.AVSession | null> {
    if (BackgroundAudio.session !== null) {
      return Promise.resolve(BackgroundAudio.session);
    }
    if (BackgroundAudio.creating !== null) {
      return BackgroundAudio.creating;
    }
    const ctx = BackgroundAudio.context;
    if (ctx === null) {
      return Promise.resolve(null);
    }
    const gen = BackgroundAudio.gen;
    BackgroundAudio.creating = BackgroundAudio.createSession(ctx).then((s: avSession.AVSession | null) => {
      BackgroundAudio.creating = null;
      if (s === null) {
        return null;
      }
      if (gen !== BackgroundAudio.gen) {
        BackgroundAudio.destroySession(s);
        return null;
      }
      BackgroundAudio.session = s;
      return s;
    });
    return BackgroundAudio.creating;
  }

  private static async createSession(ctx: common.UIAbilityContext): Promise<avSession.AVSession | null> {
    try {
      const s = await avSession.createAVSession(ctx, 'Lumen', 'video');
      s.on('play', () => BackgroundAudio.controls?.play());
      s.on('pause', () => BackgroundAudio.controls?.pause());
      s.on('stop', () => BackgroundAudio.controls?.pause());
      const agent = await BackgroundAudio.launchAgent(ctx);
      if (agent !== null) {
        await s.setLaunchAbility(agent);
      }
      BackgroundAudio.pushMetadata(s);
      await s.activate();
      return s;
    } catch (e) {
      Log.w('background', `AVSession unavailable: ${(e as Error).message ?? ''}`);
      return null;
    }
  }

  private static destroySession(s: avSession.AVSession): void {
    try {
      s.off('play');
      s.off('pause');
      s.off('stop');
    } catch (e) {
      // ignore
    }
    s.deactivate().catch(() => {}).then(() => s.destroy()).catch(() => {
      Log.w('background', 'Could not destroy AVSession');
    });
  }

  private static pushMetadata(s: avSession.AVSession): void {
    const meta: avSession.AVMetadata = {
      assetId: 'live',
      title: BackgroundAudio.title || 'Lumen',
      artist: BackgroundAudio.artist,
      duration: -1
    };
    s.setAVMetadata(meta).catch(() => {});
  }

  private static pushState(s: avSession.AVSession): void {
    const state: avSession.AVPlaybackState = {
      state: BackgroundAudio.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE
    };
    s.setAVPlaybackState(state).catch(() => {});
  }

  private static async launchAgent(ctx: common.UIAbilityContext): Promise<WantAgent | null> {
    try {
      return await wantAgent.getWantAgent({
        wants: [{ bundleName: ctx.abilityInfo.bundleName, abilityName: ctx.abilityInfo.name }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
    } catch (e) {
      return null;
    }
  }

  /** Serializes start/stop so a quick pause-play cannot leave a stray task behind. */
  private static syncTask(): void {
    if (BackgroundAudio.taskBusy || BackgroundAudio.wantTask === BackgroundAudio.taskStarted) {
      return;
    }
    const ctx = BackgroundAudio.context;
    if (ctx === null) {
      return;
    }
    BackgroundAudio.taskBusy = true;
    const starting = BackgroundAudio.wantTask;
    BackgroundAudio.runTask(ctx, starting).then(() => {
      BackgroundAudio.taskStarted = starting;
    }).catch((e: Error) => {
      Log.w('background', `${starting ? 'start' : 'stop'} audio task failed: ${e.message ?? ''}`);
      if (!starting) {
        BackgroundAudio.taskStarted = false;
      } else {
        // Do not retry in a loop; the next state change will try again.
        BackgroundAudio.wantTask = false;
      }
    }).finally(() => {
      BackgroundAudio.taskBusy = false;
      BackgroundAudio.syncTask();
    });
  }

  private static async runTask(ctx: common.UIAbilityContext, start: boolean): Promise<void> {
    if (!start) {
      await backgroundTaskManager.stopBackgroundRunning(ctx);
      return;
    }
    const agent = await BackgroundAudio.launchAgent(ctx);
    if (agent === null) {
      throw new Error('no WantAgent');
    }
    await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
      agent);
  }
}
