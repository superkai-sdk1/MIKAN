import SwiftUI

/// «Открытые чеки» of all devices: tap to continue one, swipe or long-press to delete it; «Новый чек» below.
struct OpenReceiptsSection: View {
    let receipts: Remote<[OpenReceipt]>
    /// The receipt this device's cart holds (marked «Открыт у вас»).
    let cartReceiptId: Int?
    let opening: POSOpening?
    let retry: () async -> Void
    let onOpen: (OpenReceipt) -> Void
    let onDelete: (OpenReceipt) -> Void
    let onNew: () -> Void

    private var items: [OpenReceipt] { receipts.value ?? [] }

    var body: some View {
        Section {
            HubSectionHeader(title: "Открытые чеки", detail: items.isEmpty ? nil : "\(items.count)")
            content
            NewReceiptButton(isProminent: receipts.value?.isEmpty ?? false, isWorking: opening == .newReceipt, action: onNew)
                .hubRow()
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        if receipts.value != nil {
            ForEach(items) { receipt in
                OpenReceiptRow(
                    receipt: receipt,
                    isInCart: receipt.id == cartReceiptId,
                    isOpening: opening == .receipt(receipt.id)
                ) {
                    onOpen(receipt)
                }
                .hubRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Not `.destructive`: that role removes the row before the confirmation is answered.
                    Button { onDelete(receipt) } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .contextMenu {
                    Button("Удалить чек", systemImage: "trash", role: .destructive) { onDelete(receipt) }
                }
            }
        } else if let failure = receipts.failure {
            ErrorStateView(message: failure, retry: retry)
                .cardStyle()
                .hubRow()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
                .hubRow()
        }
    }
}

/// An open receipt: who it is for, the visit, lines and total, who opened it and when, the held prepayment.
private struct OpenReceiptRow: View {
    let receipt: OpenReceipt
    let isInCart: Bool
    let isOpening: Bool
    let action: () -> Void

    private var heldDeposit: QueueDepositBadge? {
        guard let deposit = receipt.appointment?.deposit, deposit > 0 else { return nil }
        return .held(deposit)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(OpenReceiptText.who(receipt))
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        MoneyText(receipt.total)
                            .font(.headline)
                    }
                    if let appointment = receipt.appointment {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.master(appointment.master.color))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(OpenReceiptText.appointmentLine(appointment))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    Text(OpenReceiptText.details(receipt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if heldDeposit != nil || isInCart {
                        HStack(spacing: 6) {
                            if let heldDeposit { QueueDepositBadgeView(badge: heldDeposit) }
                            if isInCart { StatusBadge(text: "Открыт у вас", color: .accentColor, systemImage: "cart.fill") }
                        }
                    }
                }
                RowAccessory(isWorking: isOpening)
            }
            .foregroundStyle(.primary)
            .cardStyle(padding: 14)
            .overlay {
                if isInCart {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                }
            }
            .contentShape(.rect(cornerRadius: Theme.cardRadius))
            .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .accessibilityHint("Открыть чек. Смахните влево, чтобы удалить")
    }
}

/// «Новый чек» without an appointment; prominent while no receipt is open.
private struct NewReceiptButton: View {
    let isProminent: Bool
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Новый чек")
                        .font(.headline)
                    Text("Без записи: украшения, товары и услуги, клиента можно добавить в чеке")
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if isWorking {
                    ProgressView()
                        .tint(isProminent ? Color.white : nil)
                }
            }
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(.rect(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isProminent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: Theme.cardRadius)
        )
        .disabled(isWorking)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isProminent)
    }
}

#if DEBUG
#Preview("Открытые чеки") {
    List {
        OpenReceiptsSection(
            receipts: Remote(PreviewData.openReceipts), cartReceiptId: 8, opening: nil,
            retry: {}, onOpen: { _ in }, onDelete: { _ in }, onNew: {}
        )
    }
    .listStyle(.plain)
    .contentMargins(.horizontal, 16, for: .scrollContent)
    .auraBackground()
    .previewEnvironment()
}

#Preview("Нет открытых чеков") {
    List {
        OpenReceiptsSection(
            receipts: Remote([]), cartReceiptId: nil, opening: nil,
            retry: {}, onOpen: { _ in }, onDelete: { _ in }, onNew: {}
        )
    }
    .listStyle(.plain)
    .contentMargins(.horizontal, 16, for: .scrollContent)
    .auraBackground()
    .previewEnvironment()
}
#endif
