import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x4c55;

export class Log {
  static i(tag: string, msg: string): void {
    hilog.info(DOMAIN, `Lumen/${tag}`, '%{public}s', msg);
  }

  static w(tag: string, msg: string): void {
    hilog.warn(DOMAIN, `Lumen/${tag}`, '%{public}s', msg);
  }

  static e(tag: string, msg: string): void {
    hilog.error(DOMAIN, `Lumen/${tag}`, '%{public}s', msg);
  }
}
