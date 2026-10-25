import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from 'commons';

const PREF_NAME = 'starflow_keys';
const PREF_PREFIX = 'key_fallback_';

function strToBytes(s: string): Uint8Array {
  const enc = new util.TextEncoder();
  return enc.encodeInto(s);
}

function bytesToStr(b: Uint8Array): string {
  const dec = util.TextDecoder.create('utf-8');
  return dec.decodeToString(b);
}

/**
 * API key storage (plan D7): Asset Store Kit first; on any asset
 * unavailability (e.g. some emulators) degrade to preferences and
 * flag the low-security mode for the UI.
 */
export class AssetKeyStore {
  private ctx: common.Context | undefined = undefined;
  private assetBroken: boolean = false;
  private prefPromise: Promise<preferences.Preferences> | undefined = undefined;

  /** Must be called once at startup with the ability context. */
  bind(context: common.Context): void {
    this.ctx = context;
  }

  isLowSecurityMode(): boolean {
    return this.assetBroken;
  }

  private ensureCtx(): common.Context {
    const ctx = this.ctx;
    if (ctx === undefined) {
      throw new Error('AssetKeyStore 未绑定 context');
    }
    return ctx;
  }

  private async getPrefs(): Promise<preferences.Preferences> {
    if (this.prefPromise === undefined) {
      this.prefPromise = preferences.getPreferences(this.ensureCtx(), PREF_NAME);
    }
    return this.prefPromise;
  }

  /** Save under alias; overwrite semantics (asset.add throws on duplicate → remove first). */
  async save(alias: string, value: string): Promise<void> {
    if (!this.assetBroken) {
      try {
        const q: asset.AssetMap = new Map();
        q.set(asset.Tag.ALIAS, strToBytes(alias));
        await asset.remove(q);
      } catch (e) {
        // NOT_FOUND is fine; anything else falls through to add attempt.
      }
      try {
        const attr: asset.AssetMap = new Map();
        attr.set(asset.Tag.ALIAS, strToBytes(alias));
        attr.set(asset.Tag.SECRET, strToBytes(value));
        attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
        await asset.add(attr);
        Log.info('AssetKeyStore', `saved via asset: ${alias}`);
        return;
      } catch (e) {
        const be = e as BusinessError;
        this.assetBroken = true;
        Log.warn('AssetKeyStore', `asset unavailable (code=${be.code}), degrade to preferences`);
      }
    }
    const prefs = await this.getPrefs();
    prefs.putSync(PREF_PREFIX + alias, value);
    await prefs.flush();
    Log.info('AssetKeyStore', `saved via preferences: ${alias}`);
  }

  async load(alias: string): Promise<string | undefined> {
    if (!this.assetBroken) {
      try {
        const q: asset.AssetMap = new Map();
        q.set(asset.Tag.ALIAS, strToBytes(alias));
        q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
        const rows: Array<asset.AssetMap> = await asset.query(q);
        if (rows.length > 0) {
          const secret = rows[0].get(asset.Tag.SECRET);
          if (secret !== undefined && typeof secret !== 'boolean' && typeof secret !== 'number' && typeof secret !== 'string') {
            return bytesToStr(secret);
          }
        }
        return undefined;
      } catch (e) {
        const be = e as BusinessError;
        if (be.code !== 24000011) {
          this.assetBroken = true;
          Log.warn('AssetKeyStore', `asset query failed (code=${be.code}), degrade to preferences`);
        } else {
          return undefined;
        }
      }
    }
    const prefs = await this.getPrefs();
    const v = prefs.getSync(PREF_PREFIX + alias, '') as string;
    return v.length > 0 ? v : undefined;
  }

  async remove(alias: string): Promise<void> {
    if (!this.assetBroken) {
      try {
        const q: asset.AssetMap = new Map();
        q.set(asset.Tag.ALIAS, strToBytes(alias));
        await asset.remove(q);
      } catch (e) {
        const be = e as BusinessError;
        if (be.code !== 24000011) {
          Log.warn('AssetKeyStore', `asset remove failed (code=${be.code})`);
        }
      }
    }
    try {
      const prefs = await this.getPrefs();
      prefs.deleteSync(PREF_PREFIX + alias);
      await prefs.flush();
    } catch (e) {
      Log.warn('AssetKeyStore', 'preferences remove failed');
    }
  }
}
