import SwiftUI

/// «Наличие» of a consumable tracked as «есть / нет»: the status control and «Покупка» (a restock with what it cost)
/// in place of the stock and its operations.
struct ProductPresenceCard: View {
    let status: PresenceStatus
    let isSaving: Bool
    /// What the purchases of the last 30 days cost; `nil` when unknown or none.
    var spentRecently: Int?
    let onSelect: (PresenceStatus) -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Наличие").font(.headline)
                Spacer()
                if isSaving {
                    ProgressView()
                } else {
                    PresenceBadge(status: status)
                }
            }
            PresenceStatusPicker(selection: status, isEnabled: !isSaving, onSelect: onSelect)
            Button(action: onPurchase) {
                Label("Покупка", systemImage: "cart.badge.plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isSaving)
            .accessibilityHint("Записать покупку с суммой")
            if let spentRecently, spentRecently > 0 {
                Text(PurchaseSummary.spentText(spentRecently))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            Text("Считается без количества и при процедурах не списывается. Покупки записывайте с суммой — так расход попадёт в аналитику.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .animation(.snappy, value: status)
    }
}

#if DEBUG
#Preview {
    ProductPresenceCard(status: .low, isSaving: false, spentRecently: 3500, onSelect: { _ in }, onPurchase: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}
#endif
