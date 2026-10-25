import { Log } from 'commons';
import { SettingsKeys, SettingsRepository } from '../data/SettingsRepository';

const TAG = 'AccountService';

/**
 * 华为账号登录态（Account Kit LoginWithHuaweiIDButton 的回调结果）。
 * 只保存 openID/unionID 与登录标记，不保存 authorizationCode / idToken。
 * 云同步按 openID 归属校验；未登录时禁止上传。
 */
export class AccountService {
  static async isLoggedIn(): Promise<boolean> {
    try {
      return await SettingsRepository.getBool(SettingsKeys.HW_ACCOUNT_LOGGED_IN, false);
    } catch (e) {
      return false;
    }
  }

  static async openId(): Promise<string> {
    try {
      return await SettingsRepository.getString(SettingsKeys.HW_ACCOUNT_OPEN_ID, '');
    } catch (e) {
      return '';
    }
  }

  static async saveLogin(openId: string, unionId: string): Promise<void> {
    await SettingsRepository.set(SettingsKeys.HW_ACCOUNT_OPEN_ID, openId);
    await SettingsRepository.set(SettingsKeys.HW_ACCOUNT_UNION_ID, unionId);
    await SettingsRepository.set(SettingsKeys.HW_ACCOUNT_LOGGED_IN, true);
    Log.info(TAG, 'HUAWEI ID session saved');
  }

  static async logout(): Promise<void> {
    await SettingsRepository.remove(SettingsKeys.HW_ACCOUNT_OPEN_ID);
    await SettingsRepository.remove(SettingsKeys.HW_ACCOUNT_UNION_ID);
    await SettingsRepository.set(SettingsKeys.HW_ACCOUNT_LOGGED_IN, false);
  }

  static maskOpenId(openId: string): string {
    if (openId.length <= 6) {
      return '已登录';
    }
    return 'ID ' + openId.substring(0, 4) + '****' + openId.substring(openId.length - 2);
  }
}
