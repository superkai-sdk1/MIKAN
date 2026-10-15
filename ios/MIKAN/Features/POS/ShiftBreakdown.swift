import SwiftUI

/// Display rows of a cash shift: the drawer movements behind `expectedCash` and the shift's prepayments.
/// Display only: `expectedCash` always comes from the server and is never recomputed here.
nonisolated enum ShiftBreakdown {
    nonisolated struct Row: Hashable, Identifiable, Sendable {
        let title: String
        /// Drawer rows: signed (what the movement adds to or takes from the drawer). Prepayment rows: plain amounts.
        let amount: Int
        /// Secondary line: by-method split, the cash part.
        var detail: String?

        var id: String { title }
    }

    /// Drawer movements after the opening cash, in the order of the server's formula
    /// `opening + cash − cashRefunds + deposits.cash − deposits.cashRefunded + cashIn − cashOut`.
    /// Zero movements are left out, except cash sales.
    static func drawer(_ summary: ShiftSummary) -> [Row] {
        let sales = Row(title: "Продажи наличными", amount: summary.cash)
        let others = [
            Row(title: "Возвраты наличными", amount: -summary.cashRefunds),
            Row(title: "Предоплаты наличными", amount: summary.deposits.cash),
            Row(title: "Возвраты предоплат наличными", amount: -summary.deposits.cashRefunded),
            Row(title: "Внесения", amount: summary.cashIn),
            Row(title: "Изъятия", amount: -summary.cashOut),
        ]
        return [sales] + others.filter { $0.amount != 0 }
    }

    /// Prepayments received, applied in the shift's sales, refunded and retained; empty when there were none.
    static func deposits(_ summary: ShiftSummary) -> [Row] {
        let deposits = summary.deposits
        let received = PaymentSplit(cash: deposits.cash, card: deposits.card, transfer: deposits.transfer, qr: deposits.qr)
        let cashRefunded = deposits.cashRefunded > 0 ? "из них наличными \(Money.format(deposits.cashRefunded))" : nil
        let rows = [
            Row(title: "Получено", amount: deposits.received, detail: PaymentText.breakdown(received)),
            Row(title: "Зачтено в чеках", amount: summary.deposit),
            Row(title: "Возвращено клиентам", amount: deposits.refunded, detail: cashRefunded),
            Row(title: "Удержано (неявки и отмены)", amount: deposits.retained),
        ]
        return rows.filter { $0.amount != 0 }
    }

    /// «Предоплаты: получено 3 000 ₽ · зачтено 2 500 ₽» for the shift card; `nil` without prepayments.
    static func cardLine(_ summary: ShiftSummary) -> String? {
        let deposits = summary.deposits
        let parts = [
            ("получено", deposits.received),
            ("зачтено", summary.deposit),
            ("возвращено", deposits.refunded),
            ("удержано", deposits.retained),
        ]
        .filter { $0.1 != 0 }
        .map { "\($0.0) \(Money.format($0.1))" }
        return parts.isEmpty ? nil : "Предоплаты: " + parts.joined(separator: " · ")
    }
}

/// «На начало» and the signed drawer movements of a shift (without the expected / counted totals).
struct ShiftDrawerRows: View {
    let shift: CashShift

    var body: some View {
        LabeledContent("На начало") { MoneyText(shift.openingCash) }
        ForEach(ShiftBreakdown.drawer(shift.summary)) { row in
            ShiftBreakdownRow(row: row, signed: true)
        }
    }
}

/// «Предоплаты» of a shift; nothing when the shift had none.
struct ShiftDepositsSection: View {
    let summary: ShiftSummary

    var body: some View {
        let rows = ShiftBreakdown.deposits(summary)
        if !rows.isEmpty {
            Section("Предоплаты") {
                ForEach(rows) { row in
                    ShiftBreakdownRow(row: row, signed: false)
                }
            }
        }
    }
}

private struct ShiftBreakdownRow: View {
    let row: ShiftBreakdown.Row
    let signed: Bool

    var body: some View {
        LabeledContent {
            Text(signed ? Money.formatSigned(row.amount) : Money.format(row.amount)).monospacedDigit()
        } label: {
            Text(row.title)
            if let detail = row.detail {
                Text(detail)
            }
        }
    }
}
