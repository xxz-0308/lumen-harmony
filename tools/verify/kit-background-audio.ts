export const sessions: TestSession[] = [];
export const taskCalls: string[] = [];

export class TestSession {
  sessionId = `session-${sessions.length}`;
  listeners = new Map<string, () => void>();
  offCalls = 0;
  destroyCalls = 0;
  deactivated = false;
  private finishDeactivate!: () => void;
  private deactivateDone = new Promise<void>(resolve => { this.finishDeactivate = resolve; });

  on(name: string, callback: () => void) { this.listeners.set(name, callback); }
  off() { this.offCalls++; throw new Error('synchronous off must not run during room exit'); }
  setLaunchAbility() { return Promise.resolve(); }
  setAVMetadata() { return Promise.resolve(); }
  setAVPlaybackState() { return Promise.resolve(); }
  activate() { return Promise.resolve(); }
  deactivate() { this.deactivated = true; return this.deactivateDone; }
  completeDeactivate() { this.finishDeactivate(); }
  destroy() { this.destroyCalls++; return Promise.resolve(); }
  emit(name: string) { this.listeners.get(name)?.(); }
}

export const avSession = {
  PlaybackState: { PLAYBACK_STATE_PLAY: 1, PLAYBACK_STATE_PAUSE: 2 },
  createAVSession: async () => { const session = new TestSession(); sessions.push(session); return session; }
};
export const wantAgent = {
  OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 },
  getWantAgent: async () => ({})
};
export const backgroundTaskManager = {
  BackgroundMode: { AUDIO_PLAYBACK: 1 },
  startBackgroundRunning: async () => { taskCalls.push('start'); },
  stopBackgroundRunning: async () => { taskCalls.push('stop'); }
};
