import { common } from '@kit.AbilityKit';
import { BiliAccount, BiliQrLogin } from '../core/sites/BiliQrLogin';
import { Sites } from '../core/sites/Sites';
import { BiliCredentials } from '../platform/BiliCredentials';
import { Log } from '../util/Log';
import { Settings } from './Settings';

export class BiliSession {
  private static context: common.Context | null = null;
  private static storage: BiliCredentials | null = null;

  private static store(): BiliCredentials {
    if (BiliSession.storage === null) {
      if (BiliSession.context === null) {
        throw new Error('账号存储尚未就绪');
      }
      BiliSession.storage = new BiliCredentials(BiliSession.context);
    }
    return BiliSession.storage;
  }

  static async restore(context: common.Context): Promise<void> {
    BiliSession.context = context;
    let cookie = '';
    const legacy = Settings.inst.legacyBiliCookie;
    const oldUid = Settings.inst.biliUid;
    const oldName = Settings.inst.biliName;
    try {
      const storage = BiliSession.store();
      try {
        cookie = await storage.load();
      } catch (e) {
        Settings.inst.accountError = '登录记录损坏，请重新扫码登录';
        Log.w('bili-auth', 'Could not decrypt saved session');
      }
      if (!cookie && legacy) {
        await storage.save(legacy);
        cookie = legacy;
      }
      const match = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)(?:;|$)/);
      const uid = match ? Number(match[1]) : 0;
      if (cookie && /(?:^|;\s*)SESSDATA=[^;]+/.test(cookie) && uid > 0) {
        if (Settings.inst.biliUid !== uid) {
          Settings.inst.biliName = '';
        }
        Settings.inst.biliUid = uid;
        Settings.inst.accountError = '';
        Sites.bilibili.setCookie(cookie, uid);
        BiliSession.validateLater(cookie);
      } else {
        Sites.bilibili.setCookie('', 0);
        Settings.inst.biliUid = 0;
        Settings.inst.biliName = '';
      }
    } catch (e) {
      Log.w('bili-auth', 'Could not restore saved session');
      Settings.inst.accountError = '账号存储暂不可用，请稍后重试';
      Sites.bilibili.setCookie('', 0);
      Settings.inst.biliUid = 0;
      Settings.inst.biliName = '';
    } finally {
      // A previous build wrote the credential into the general settings JSON.
      // Scrub it even if migration fails; never keep an unprotected fallback.
      Settings.inst.legacyBiliCookie = '';
      if (legacy || oldUid !== Settings.inst.biliUid || oldName !== Settings.inst.biliName) {
        await Settings.inst.flush().catch(() => {});
      }
      Settings.inst.publishAccount();
    }
  }

  /** Signs out quietly if Bilibili says the restored session has expired or was revoked. */
  private static validateLater(cookie: string): void {
    new BiliQrLogin().check(cookie).then(async (valid: boolean | null) => {
      if (valid !== false || Sites.bilibili.cookie !== cookie) {
        return;
      }
      Log.i('bili-auth', 'Saved session expired');
      await BiliSession.signOut();
      if (Sites.bilibili.cookie.length > 0) {
        return;
      }
      Settings.inst.biliExpired = true;
      Settings.inst.publishAccount();
      await Settings.inst.flush().catch(() => Log.w('bili-auth', 'Could not save expired session status'));
    }).catch(() => {
      Log.w('bili-auth', 'Could not clear expired session');
    });
  }

  static async signIn(account: BiliAccount): Promise<void> {
    Log.i('bili-auth', 'Verified account; saving credential');
    try {
      await BiliSession.store().save(account.cookie);
    } catch (e) {
      Log.w('bili-auth', 'Credential save failed');
      throw new Error('B站凭据保存失败');
    }
    Log.i('bili-auth', 'Credential saved');
    Sites.bilibili.setCookie(account.cookie, account.userId);
    Settings.inst.biliUid = account.userId;
    Settings.inst.biliName = account.name;
    Settings.inst.biliExpired = false;
    Settings.inst.accountError = '';
    Settings.inst.publishAccount();
    await Settings.inst.flush().catch(() => {
      Log.w('bili-auth', 'Could not save account label');
    });
  }

  static async signOut(): Promise<void> {
    await BiliSession.store().clear();
    Sites.bilibili.setCookie('', 0);
    Settings.inst.biliUid = 0;
    Settings.inst.biliName = '';
    Settings.inst.accountError = '';
    Settings.inst.publishAccount();
    await Settings.inst.flush().catch(() => {
      Log.w('bili-auth', 'Could not save account label');
    });
  }
}
