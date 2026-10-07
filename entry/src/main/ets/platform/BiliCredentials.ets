import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { Base64, Utf8 } from '../core/common/Bytes';
import { Log } from '../util/Log';

const ALIAS = 'com.zyf.lumen.bili.session.v1';
const STORED = 'session_v1';
const AAD = Utf8.encode('Lumen Bilibili session v1');

/** HUKS holds the AES key; Preferences contain only authenticated ciphertext and its random nonce. */
export class BiliCredentials {
  private static ensuringKey: Promise<void> | null = null;
  private prefs: preferences.Preferences;

  constructor(context: common.Context) {
    this.prefs = preferences.getPreferencesSync(context, { name: 'lumen_credentials' });
  }

  private async ensureKey(): Promise<void> {
    if (BiliCredentials.ensuringKey !== null) {
      return BiliCredentials.ensuringKey;
    }
    const operation = this.createKeyIfNeeded();
    BiliCredentials.ensuringKey = operation;
    try {
      await operation;
    } finally {
      if (BiliCredentials.ensuringKey === operation) {
        BiliCredentials.ensuringKey = null;
      }
    }
  }

  private async createKeyIfNeeded(): Promise<void> {
    let exists = false;
    try {
      exists = await huks.hasKeyItem(ALIAS, {});
    } catch (e) {
      Log.w('bili-auth', `HUKS lookup failed code=${(e as BusinessError).code}`);
      throw new Error('HUKS key lookup failed');
    }
    if (exists) {
      Log.i('bili-auth', 'HUKS key already exists');
      return;
    }
    const opts: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_128 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT }
      ]
    };
    try {
      await huks.generateKeyItem(ALIAS, opts);
    } catch (e) {
      Log.w('bili-auth', `HUKS key generation failed code=${(e as BusinessError).code}`);
      throw new Error('HUKS key generation failed');
    }
  }

  private options(purpose: huks.HuksKeyPurpose, nonce: Uint8Array, input: Uint8Array,
    tag?: Uint8Array): huks.HuksOptions {
    const properties: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_128 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: AAD }
    ];
    if (tag) {
      properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag });
    }
    return { properties, inData: input };
  }

  private async process(options: huks.HuksOptions): Promise<Uint8Array> {
    const session = await huks.initSession(ALIAS, options);
    try {
      const output = await huks.finishSession(session.handle, options);
      if (!output.outData) {
        throw new Error('HUKS did not return data');
      }
      return output.outData;
    } catch (e) {
      await huks.abortSession(session.handle, {}).catch(() => {});
      throw new Error('HUKS session failed');
    }
  }

  async save(cookie: string): Promise<void> {
    if (!cookie || cookie.length > 8192) {
      throw new Error('Invalid session');
    }
    Log.i('bili-auth', 'Credential save: key');
    await this.ensureKey();
    Log.i('bili-auth', 'Credential save: nonce');
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    Log.i('bili-auth', 'Credential save: encryption');
    const cipher = await this.process(this.options(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT,
      nonce, Utf8.encode(cookie)));
    if (cipher.length < 17) {
      throw new Error('HUKS encryption failed');
    }
    Log.i('bili-auth', 'Credential save: preferences');
    this.prefs.putSync(STORED, `1:${Base64.encode(nonce)}:${Base64.encode(cipher)}`);
    await this.prefs.flush();
    Log.i('bili-auth', 'Credential save: flushed');
  }

  async load(): Promise<string> {
    const record = this.prefs.getSync(STORED, '') as string;
    if (!record) {
      return '';
    }
    const parts = record.split(':');
    if (parts.length !== 3 || parts[0] !== '1' || parts[1].length !== 16 || parts[2].length > 16384) {
      throw new Error('Invalid stored session');
    }
    const nonce = Base64.decode(parts[1]);
    const cipher = Base64.decode(parts[2]);
    if (nonce.length !== 12 || cipher.length < 17) {
      throw new Error('Invalid stored session');
    }
    const plain = await this.process(this.options(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      nonce, cipher.slice(0, cipher.length - 16), cipher.slice(cipher.length - 16)));
    return Utf8.decode(plain);
  }

  async clear(): Promise<void> {
    this.prefs.deleteSync(STORED);
    await this.prefs.flush();
  }
}
