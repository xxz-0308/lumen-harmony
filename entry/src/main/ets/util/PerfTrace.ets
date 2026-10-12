import { hiTraceMeter } from '@kit.PerformanceAnalysisKit';

/** Named synchronous scopes for device traces; no room IDs, URLs or chat content. */
export class PerfTrace {
  static run(name: string, work: () => void): void {
    hiTraceMeter.startSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL, `Lumen:${name}`);
    try {
      work();
    } finally {
      hiTraceMeter.finishSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL);
    }
  }
}
