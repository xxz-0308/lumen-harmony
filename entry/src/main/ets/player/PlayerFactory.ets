import { Settings } from '../app/Settings';
import { IjkLivePlayer } from './IjkLivePlayer';
import { LivePlayer } from './LivePlayer';
import { LivePlayerApi, PlayerEngine } from './PlayerApi';

/** Chosen when a room opens; switching in settings applies to the next room. */
export function createLivePlayer(): LivePlayerApi {
  const engine = Settings.inst.playerEngine === 'avplayer' ? PlayerEngine.AvPlayer : PlayerEngine.Ijk;
  return engine === PlayerEngine.Ijk ? new IjkLivePlayer() : new LivePlayer();
}
