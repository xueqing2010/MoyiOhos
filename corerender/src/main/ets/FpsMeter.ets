import displaySync from '@ohos.graphics.displaySync';
import { Log } from 'commons';

/**
 * Frame-rate meter driven by displaySync 'frame' callbacks (plan D5).
 * Reports measured fps roughly once per second.
 */
export class FpsMeter {
  private sync: displaySync.DisplaySync | undefined = undefined;
  private frameCount: number = 0;
  private windowStartNs: number = 0;
  private running: boolean = false;

  start(onFps: (fps: number) => void): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.frameCount = 0;
    this.windowStartNs = 0;
    try {
      const sync = displaySync.create();
      const range: ExpectedFrameRateRange = { min: 30, max: 120, expected: 60 };
      sync.setExpectedFrameRateRange(range);
      sync.on('frame', (info: displaySync.IntervalInfo) => {
        if (!this.running) {
          return;
        }
        if (this.windowStartNs === 0) {
          this.windowStartNs = info.timestamp;
          this.frameCount = 0;
        }
        this.frameCount++;
        const elapsedNs = info.timestamp - this.windowStartNs;
        if (elapsedNs >= 1_000_000_000) {
          const fps = this.frameCount * 1_000_000_000 / elapsedNs;
          onFps(Math.round(fps * 10) / 10);
          this.windowStartNs = info.timestamp;
          this.frameCount = 0;
        }
      });
      sync.start();
      this.sync = sync;
    } catch (e) {
      Log.error('FpsMeter', `displaySync unavailable: ${JSON.stringify(e)}`);
      this.running = false;
    }
  }

  stop(): void {
    this.running = false;
    const sync = this.sync;
    if (sync !== undefined) {
      try {
        sync.stop();
      } catch (e) {
        Log.warn('FpsMeter', 'stop failed');
      }
      this.sync = undefined;
    }
  }

  isRunning(): boolean {
    return this.running;
  }
}
