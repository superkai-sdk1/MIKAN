import SwiftUI

/// «Предоплаты» of a report period: received (by method), applied in sales, refunded, retained,
/// and what is still held for appointments at the end of the period.
struct ReportDepositsCard: View {
    let deposits: ReportDeposits

    private var receivedByMethod: String? {
        PaymentText.breakdown(PaymentSplit(cash: deposits.cash, card: deposits.card, transfer: deposits.transfer, qr: deposits.qr))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Предоплаты").font(.headline)
            ReportDepositRow(title: "Получено", amount: deposits.received, detail: receivedByMethod)
            ReportDepositRow(title: "Зачтено в чеках", amount: deposits.applied)
            ReportDepositRow(title: "Возвращено клиентам", amount: deposits.refunded)
            ReportDepositRow(title: "Удержано (неявки и отмены)", amount: deposits.retained)
            Divider()
            ReportDepositRow(title: "На руках на конец периода", amount: deposits.held, isEmphasized: true)
            Text("Предоплата попадает в выручку, когда её зачитывают в чеке. Удержанные предоплаты в выручку не входят.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

private struct ReportDepositRow: View {
    let title: String
    let amount: Int
    var detail: String?
    var isEmphasized = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            MoneyText(amount)
        }
        .font(.subheadline.weight(isEmphasized ? .semibold : .regular))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    ScrollView {
        ReportDepositsCard(deposits: PreviewData.report.deposits ?? .zero)
            .padding()
    }
}
#endif
