import SwiftUI

/// «Открыть чек без записи», or «Продолжить чек · N ₽» + «Новый чек» while a receipt is open.
struct ReceiptEntryCard: View {
    @Environment(CartStore.self) private var cart
    let onContinue: () -> Void
    let onNew: () -> Void

    private var isOpen: Bool {
        ReceiptDraft.isOpen(lines: cart.lines, client: cart.client, appointment: cart.appointment)
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if isOpen {
                    Button(action: onContinue) {
                        EntryLabel(
                            title: ReceiptDraft.continueTitle(lineCount: cart.lines.count, total: cart.total),
                            subtitle: ReceiptDraft.summary(itemCount: cart.itemCount, client: cart.client, appointment: cart.appointment),
                            systemImage: "cart.fill",
                            isProminent: true
                        )
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: Theme.cardRadius))

                    Button(action: onNew) {
                        EntryLabel(title: "Новый чек", subtitle: "Начать с пустого чека без записи", systemImage: "plus", isProminent: false)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.cardRadius))
                } else {
                    Button(action: onNew) {
                        EntryLabel(
                            title: "Открыть чек без записи",
                            subtitle: "Украшения и услуги, клиента можно добавить в чеке",
                            systemImage: "receipt",
                            isProminent: true
                        )
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: Theme.cardRadius))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isOpen)
    }
}

private struct EntryLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isProminent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.8)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(isProminent ? Color.white : Color.primary)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
    }
}

/// «К оплате по записям»: today's appointments without a sale.
struct PaymentQueueSection: View {
    let queue: Remote<[Appointment]>
    /// Appointment the open receipt pays for (marked «В чеке»).
    let openAppointmentId: Int?
    let retry: () async -> Void
    let onSelect: (Appointment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("К оплате по записям")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                if let count = queue.value?.count, count > 0 {
                    Text(Plural.appointments(count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let appointments = queue.value {
            if appointments.isEmpty {
                emptyCard
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(appointments) { appointment in
                        PaymentQueueRow(appointment: appointment, isInReceipt: appointment.id == openAppointmentId) {
                            onSelect(appointment)
                        }
                    }
                }
            }
        } else if let failure = queue.failure {
            ErrorStateView(message: failure, retry: retry)
                .cardStyle()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Сегодня нет записей к оплате")
                .font(.subheadline.weight(.semibold))
            Text("Здесь появятся сегодняшние записи, которые ещё не оплачены.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Appointment awaiting payment: time, master color, client, service, price, deposit, status.
private struct PaymentQueueRow: View {
    let appointment: Appointment
    let isInReceipt: Bool
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
                        Text(appointment.client.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text("\(appointment.displayTitle) · \(appointment.master.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        MoneyText(appointment.price)
                            .font(.subheadline.weight(.semibold))
                        if appointment.deposit > 0 {
                            StatusBadge(text: "Предоплата \(Money.format(appointment.deposit))", color: .indigo)
                        }
                        Spacer(minLength: 0)
                        if isInReceipt {
                            StatusBadge(text: "В чеке", color: .accentColor, systemImage: "cart.fill")
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .cardStyle(padding: 14)
            .contentShape(.rect(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint(isInReceipt ? "Вернуться к открытому чеку" : "Открыть чек по записи")
    }
}
