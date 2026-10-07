import { audio } from '@kit.AudioKit';
import { Log } from '../util/Log';

/** Device media-stream volume, distinct from AVPlayer's per-stream gain. */
export class MediaVolume {
  private static range(): number[] | null {
    try {
      const group = audio.getAudioManager().getVolumeManager()
        .getVolumeGroupManagerSync(audio.DEFAULT_VOLUME_GROUP_ID);
      return [group.getMinVolumeSync(audio.AudioVolumeType.MEDIA),
        group.getMaxVolumeSync(audio.AudioVolumeType.MEDIA),
        group.getVolumeSync(audio.AudioVolumeType.MEDIA)];
    } catch (e) {
      Log.w('volume', 'Could not read media volume');
      return null;
    }
  }

  static read(): number | null {
    const range = MediaVolume.range();
    return range !== null && range[1] > range[0] ?
      (range[2] - range[0]) / (range[1] - range[0]) : null;
  }

  static async write(value: number): Promise<boolean> {
    const range = MediaVolume.range();
    if (range === null || range[1] <= range[0]) {
      return false;
    }
    const level = Math.round(range[0] + Math.max(0, Math.min(1, value)) * (range[1] - range[0]));
    if (level === range[2]) {
      return true;
    }
    try {
      await audio.getAudioManager().setVolume(audio.AudioVolumeType.MEDIA, level);
      return true;
    } catch (e) {
      Log.w('volume', 'Could not change media volume');
      return false;
    }
  }
}
