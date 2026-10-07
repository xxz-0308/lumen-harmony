/** Pure, cumulative native-buffer diagnostics; durations use wallclock ms with negative deltas clamped.
 * observedMs includes pauses; exposedMs only includes requested playback after this source's first frame.
 * A valid buffer starts during exposure. Pause/source teardown truncates it; it never bridges sources.
 * Raw totals also include startup/inactive buffers. Snapshots include an unfinished interval, once.
 */
export class BufferStats {
  private observedAt: number = -1;
  private observedMs: number = 0;
  private exposedAt: number = -1;
  private exposedMs: number = 0;
  private pendingAt: number = -1;
  private pendingValid: boolean = false;
  private cachedMs: number = -1;
  private cachedAt: number = -1;
  private starts: number = 0;
  private ends: number = 0;
  private pairs: number = 0;
  private duplicateStarts: number = 0;
  private orphanEnds: number = 0;
  private interrupted: number = 0;
  private validCount: number = 0;
  private totalMs: number = 0;
  private maxMs: number = 0;
  private rawTotalMs: number = 0;
  private rawMaxMs: number = 0;

  observe(now: number): void {
    if (this.observedAt < 0) {
      this.observedAt = now;
    }
  }

  expose(active: boolean, now: number): void {
    if (active && this.exposedAt < 0 && this.observedAt >= 0) {
      this.exposedAt = now;
    } else if (!active && this.exposedAt >= 0) {
      this.exposedMs += this.elapsed(this.exposedAt, now);
      this.exposedAt = -1;
    }
  }

  stop(now: number): void {
    this.expose(false, now);
    if (this.observedAt >= 0) {
      this.observedMs += this.elapsed(this.observedAt, now);
      this.observedAt = -1;
    }
  }

  clearCache(): void {
    this.cachedMs = -1;
    this.cachedAt = -1;
  }

  cache(value: number, now: number): void {
    // BUFFERING CACHED_DURATION is already milliseconds (unlike playback-info cacheduration).
    this.cachedMs = Number.isFinite(value) && value >= 0 ? value : -1;
    this.cachedAt = this.cachedMs >= 0 ? now : -1;
  }

  cacheText(now: number): string {
    // This is the last native event, NOT remaining buffer at the time of a later START.
    // Native reports are sparse; neither an old positive value nor its age rules out starvation.
    return `cacheSample=last-event cachedMs=${this.cachedMs}` +
      ` cacheAgeMs=${this.cachedAt < 0 ? -1 : this.elapsed(this.cachedAt, now)}`;
  }

  start(now: number): string {
    this.starts++;
    if (this.pendingAt >= 0) {
      this.duplicateStarts++;
      return `pair=duplicate-start valid=${this.pendingValid} stallMs=${this.elapsed(this.pendingAt, now)}`;
    }
    this.pendingAt = now;
    this.pendingValid = this.exposedAt >= 0;
    if (this.pendingValid) {
      this.validCount++;
    }
    return `pair=start valid=${this.pendingValid} stallMs=0`;
  }

  end(now: number): string {
    this.ends++;
    if (this.pendingAt < 0) {
      // Includes duplicate END: no matching START, so no fabricated duration or valid sample.
      this.orphanEnds++;
      return 'pair=orphan-end valid=false stallMs=-1';
    }
    this.pairs++;
    return `pair=paired ${this.close(now)}`;
  }

  interrupt(now: number): string {
    if (this.pendingAt < 0) {
      return '';
    }
    this.interrupted++;
    return `pair=interrupted ${this.close(now)}`;
  }

  summary(now: number): string {
    const pendingMs = this.pendingAt < 0 ? 0 : this.elapsed(this.pendingAt, now);
    const validPendingMs = this.pendingValid ? pendingMs : 0;
    return `clock=wallclock-ms negativeDelta=clamp scope=cumulative` +
      ` observedMs=${this.observedMs + (this.observedAt < 0 ? 0 : this.elapsed(this.observedAt, now))}` +
      ` exposedMs=${this.exposedMs + (this.exposedAt < 0 ? 0 : this.elapsed(this.exposedAt, now))}` +
      ` validCount=${this.validCount} totalMs=${this.totalMs + validPendingMs}` +
      ` maxMs=${Math.max(this.maxMs, validPendingMs)}` +
      ` rawStart=${this.starts} rawEnd=${this.ends} paired=${this.pairs}` +
      ` duplicateStart=${this.duplicateStarts} orphanEnd=${this.orphanEnds} interrupted=${this.interrupted}` +
      ` rawTotalMs=${this.rawTotalMs + pendingMs} rawMaxMs=${Math.max(this.rawMaxMs, pendingMs)}` +
      ` pending=${this.pendingAt >= 0} pendingValid=${this.pendingValid}`;
  }

  private close(now: number): string {
    const ms = this.elapsed(this.pendingAt, now);
    const result = `valid=${this.pendingValid} stallMs=${ms}`;
    this.rawTotalMs += ms;
    this.rawMaxMs = Math.max(this.rawMaxMs, ms);
    if (this.pendingValid) {
      this.totalMs += ms;
      this.maxMs = Math.max(this.maxMs, ms);
    }
    this.pendingAt = -1;
    this.pendingValid = false;
    return result;
  }

  private elapsed(start: number, now: number): number {
    return Math.max(0, now - start);
  }
}
