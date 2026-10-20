import type { AppContext } from '../context.js';

/**
 * The client's Telegram messages about a sale (docs/API.md «Receipt in Telegram»): the receipt after a paid sale
 * and the notice of a refund. Both never throw — the sale or refund is already recorded; staff can resend the receipt.
 */
export async function sendSaleReceipt(_ctx: AppContext, _saleId: number): Promise<void> {
  // Implemented in the «receipt to the client» change.
}

export async function sendRefundNotice(_ctx: AppContext, _refundId: number): Promise<void> {
  // Implemented in the «receipt to the client» change.
}
