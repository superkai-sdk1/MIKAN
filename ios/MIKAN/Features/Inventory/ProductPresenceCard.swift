import SwiftUI

/// «Наличие» of a consumable tracked as «есть / нет»: the status control in place of the stock and its operations.
struct ProductPresenceCard: View {
    let status: PresenceStatus
    let isSaving: Bool
    let onSelect: (PresenceStatus) -> Void

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
            Text("Считается без количества: отметьте, когда начинает заканчиваться и когда закончился. Со склада при процедурах не списывается.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .animation(.snappy, value: status)
    }
}

#if DEBUG
#Preview {
    ProductPresenceCard(status: .low, isSaving: false) { _ in }
        .padding()
        .background(Color(.systemGroupedBackground))
}
#endif
