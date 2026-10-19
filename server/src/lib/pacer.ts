/** Time source of background senders: the real clock in production, a fake one in tests. */
export interface Clock {
  now(): number;
  sleep(ms: number): Promise<void>;
}

export const realClock: Clock = {
  now: () => Date.now(),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

/**
 * Spaces out sends so that at most `perSecond` go out in any second (one every `1000 / perSecond` ms): bulk Telegram
 * messages stay well below the API limits.
 */
export class Pacer {
  private readonly intervalMs: number;
  private nextAt = 0;

  constructor(
    private readonly clock: Clock,
    perSecond: number,
  ) {
    this.intervalMs = 1000 / perSecond;
  }

  /** Resolves when the next send may go out. */
  async wait(): Promise<void> {
    const delay = this.nextAt - this.clock.now();
    if (delay > 0) await this.clock.sleep(delay);
    this.nextAt = Math.max(this.clock.now(), this.nextAt) + this.intervalMs;
  }
}
