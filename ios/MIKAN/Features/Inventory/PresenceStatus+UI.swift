import SwiftUI

// Availability of consumables tracked as «есть / заканчивается / нет»: colours, the badge and the status control.

extension PresenceStatus {
    var color: Color {
        switch self {
        case .ok: .green
        case .low: .orange
        case .out: .red
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .low: "exclamationmark.triangle.fill"
        case .out: "xmark.circle.fill"
        }
    }

    /// The swipe action that sets it: «Есть», «Мало», «Нет».
    var shortTitle: String {
        switch self {
        case .ok: "Есть"
        case .low: "Мало"
        case .out: "Нет"
        }
    }
}

/// Status pill of a presence consumable, in place of the stock quantity.
struct PresenceBadge: View {
    let status: PresenceStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol).imageScale(.small)
            Text(status.title)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(status.color)
        .background(status.color.opacity(0.15), in: .capsule)
        .accessibilityLabel("Наличие: \(status.title)")
    }
}

/// Three big buttons «Есть · Заканчивается · Нет». `suggested` (outlined) is what the system expects before the status
/// is marked — in a stock count tapping it confirms it.
struct PresenceStatusPicker: View {
    let selection: PresenceStatus?
    var suggested: PresenceStatus?
    var isEnabled = true
    let onSelect: (PresenceStatus) -> Void

    private static let minHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PresenceStatus.allCases) { status in
                segment(status)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Наличие")
    }

    private func segment(_ status: PresenceStatus) -> some View {
        let isSelected = selection == status
        let isSuggested = selection == nil && suggested == status
        return Button {
            onSelect(status)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: status.symbol).imageScale(.small)
                Text(status.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: Self.minHeight)
            .padding(.horizontal, 4)
            .foregroundStyle(isSelected ? Color.white : status.color)
            .background(isSelected ? status.color : status.color.opacity(0.12), in: .rect(cornerRadius: 12))
            .overlay {
                if isSuggested {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(status.color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityLabel(status.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSuggested ? "Ожидается. Нажмите, чтобы подтвердить" : "")
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        HStack {
            ForEach(PresenceStatus.allCases) { PresenceBadge(status: $0) }
        }
        PresenceStatusPicker(selection: .low) { _ in }
        PresenceStatusPicker(selection: nil, suggested: .ok) { _ in }
    }
    .padding()
}
#endif
