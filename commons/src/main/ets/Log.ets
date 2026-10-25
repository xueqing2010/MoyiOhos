import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * Thin hilog wrapper with a fixed domain and per-call tags.
 */
export class Log {
  private static readonly DOMAIN: number = 0x0301;

  static debug(tag: string, msg: string): void {
    hilog.debug(Log.DOMAIN, tag, '%{public}s', msg);
  }

  static info(tag: string, msg: string): void {
    hilog.info(Log.DOMAIN, tag, '%{public}s', msg);
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(Log.DOMAIN, tag, '%{public}s', msg);
  }

  static error(tag: string, msg: string): void {
    hilog.error(Log.DOMAIN, tag, '%{public}s', msg);
  }
}
