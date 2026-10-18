import SwiftUI

/// What the hub is opening right now (its row shows a spinner; other taps wait).
enum POSOpening: Hashable {
    case receipt(Int)
    case visit(appointmentId: Int)
    case newReceipt
}

extension View {
    /// A card row of the POS hub list: no row background, separators or side insets.
    func hubRow(top: CGFloat = 5, bottom: CGFloat = 5) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// «Удалить чек?» with what deleting changes; `onDelete` runs on «Удалить чек».
    func receiptDeletionDialog(_ deletion: Binding<ReceiptDeletion?>, onDelete: @escaping (ReceiptDeletion) -> Void) -> some View {
        confirmationDialog(
            OpenReceiptText.deleteTitle,
            isPresented: Binding(
                get: { deletion.wrappedValue != nil },
                set: { if !$0 { deletion.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletion.wrappedValue
        ) { receipt in
            Button("Удалить чек", role: .destructive) { onDelete(receipt) }
            Button("Отмена", role: .cancel) {}
        } message: { receipt in
            Text(receipt.message)
        }
    }
}

/// Title of a hub section with an optional count on the right; a list row of its own.
struct HubSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .hubRow(top: 16, bottom: 2)
    }
}

/// «К оплате по записям»: today's unpaid appointments whose visit has not started (no open receipt).
/// A tap starts the visit: the appointment moves to the open receipts.
struct PaymentQueueSection: View {
    let queue: Remote<[Appointment]>
    let openReceipts: [OpenReceipt]
    let opening: POSOpening?
    let retry: () async -> Void
    let onStart: (Appointment) -> Void

    private var appointments: [Appointment]? {
        queue.value.map { PaymentQueue.notStarted($0, openReceipts: openReceipts) }
    }

    var body: some View {
        Section {
            HubSectionHeader(title: "К оплате по записям", detail: appointments.flatMap { $0.isEmpty ? nil : Plural.appointments($0.count) })
            content
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        if let appointments {
            if appointments.isEmpty {
                emptyCard.hubRow()
            } else {
                ForEach(appointments) { appointment in
                    PaymentQueueRow(appointment: appointment, isStarting: opening == .visit(appointmentId: appointment.id)) {
                        onStart(appointment)
                    }
                    .hubRow()
                }
            }
        } else if let failure = queue.failure {
            ErrorStateView(message: failure, retry: retry)
                .cardStyle()
                .hubRow()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .hubRow()
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Сегодня нет записей к оплате")
                .font(.subheadline.weight(.semibold))
            Text("Здесь появятся сегодняшние неоплаченные записи. Начатые визиты — в открытых чеках.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Appointment awaiting payment: time, master color, client, service, price, prepayment, status.
private struct PaymentQueueRow: View {
    let appointment: Appointment
    let isStarting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(DateText.timeRange(appointment.startsAt, appointment.endsAt))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Spacer(minLength: 8)
                        AppointmentStatusBadge(status: appointment.status)
                    }
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.master(appointment.master.color))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(appointment.client.fullName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text("\(appointment.displayTitle) · \(appointment.master.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    QueuePriceLine(appointment: appointment)
                }
                RowAccessory(isWorking: isStarting)
            }
            .foregroundStyle(.primary)
            .cardStyle(padding: 14)
            .contentShape(.rect(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .accessibilityHint("Начать визит: откроется чек с услугами, клиентом и предоплатой")
    }
}

/// Price and the prepayment badge; the badge moves to its own line when they do not fit.
private struct QueuePriceLine: View {
    let appointment: Appointment

    private var badge: QueueDepositBadge? { PaymentQueue.depositBadge(for: appointment) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                price
                if let badge { QueueDepositBadgeView(badge: badge) }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                price
                if let badge { QueueDepositBadgeView(badge: badge) }
            }
        }
    }

    private var price: some View {
        MoneyText(appointment.price)
            .font(.subheadline.weight(.semibold))
    }
}

/// «Предоплата N ₽» (held, applied at checkout) or «Ждём предоплату N ₽» (required, not received yet).
struct QueueDepositBadgeView: View {
    let badge: QueueDepositBadge

    var body: some View {
        switch badge {
        case .held:
            StatusBadge(text: badge.text, color: .green, systemImage: PaymentLine.depositSymbol)
        case .waiting:
            StatusBadge(text: badge.text, color: .orange, systemImage: "hourglass")
        }
    }
}

/// Chevron of a hub row, or a spinner while it is being opened.
struct RowAccessory: View {
    let isWorking: Bool

    var body: some View {
        Group {
            if isWorking {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 20)
        .accessibilityHidden(true)
    }
}
