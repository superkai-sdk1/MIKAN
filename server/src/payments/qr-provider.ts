/** What the bank says about a QR code: not paid yet, paid, or the payment was declined. */
export type QrBankStatus = 'pending' | 'paid' | 'rejected';

export interface CreatedQr {
  /** The bank's id of the QR code, used to ask for its status. */
  externalId: string;
  /** The link encoded into the QR image; opens the client's bank app. */
  payload: string;
}

/** A bank that issues one-off (dynamic) SBP QR codes. Tochka in production, a fake in tests. */
export interface QrProvider {
  readonly name: string;
  /** `amount` in whole rubles; the code stops accepting payments after `ttlMinutes`. */
  createQr(input: { amount: number; purpose: string; ttlMinutes: number }): Promise<CreatedQr>;
  paymentStatus(externalId: string): Promise<QrBankStatus>;
}

/**
 * A bank call failed (network, auth, validation on the bank side). The message is safe to log, not to show.
 * `status` is the bank's HTTP status when it answered with an error.
 */
export class QrProviderError extends Error {
  constructor(
    message: string,
    readonly status?: number,
  ) {
    super(message);
    this.name = 'QrProviderError';
  }
}
