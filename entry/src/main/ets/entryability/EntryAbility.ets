import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { installOhPlatform } from '../platform/OhPlatform';
import { AppEnv } from '../app/AppEnv';
import { Settings } from '../app/Settings';
import { FollowStore, HistoryStore } from '../app/Stores';
import { BiliSession } from '../app/BiliSession';
import { Log } from '../util/Log';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    installOhPlatform();
    AppEnv.init(this.context);
    Settings.inst.load(this.context);
    FollowStore.inst.load(this.context);
    HistoryStore.inst.load(this.context);
    AppEnv.inst.setThemeMode(Settings.inst.themeMode);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.loadWindow(windowStage).catch(() => {});
  }

  private async loadWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      await BiliSession.restore(this.context);
    } catch (e) {
      Log.w('bili-auth', 'Unable to initialize account storage');
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Log.e('ability', `loadContent failed ${err.code} ${err.message}`);
        return;
      }
      AppEnv.attachWindow(windowStage.getMainWindowSync());
    });
  }

  onWindowStageDestroy(): void {
    AppEnv.detachWindow();
  }

  onDestroy(): void {
    Settings.inst.flushOnExit();
    AppEnv.detachWindow();
    AppEnv.inst.context = null;
  }

  onForeground(): void {
    Log.i('ability', 'foreground');
    AppEnv.setAbilityForeground(true);
  }

  onBackground(): void {
    Log.i('ability', 'background');
    AppEnv.setAbilityForeground(false);
    Settings.inst.flush().catch(() => {});
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppEnv.syncSystemColorMode(newConfig);
  }
}
