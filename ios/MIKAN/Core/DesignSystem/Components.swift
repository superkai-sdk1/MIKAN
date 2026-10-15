import SwiftUI

/// Small tinted capsule label: statuses, kinds, flags.
struct StatusBadge: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.15), in: .capsule)
    }
}

struct InitialsAvatar: View {
    let name: String
    var color: Color = .accentColor
    var size: CGFloat = 40

    var body: some View {
        Text(Initials.from(name))
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: .circle)
            .accessibilityHidden(true)
    }
}

struct MoneyText: View {
    let amount: Int
    var isFrom = false

    init(_ amount: Int, from isFrom: Bool = false) {
        self.amount = amount
        self.isFrom = isFrom
    }

    var body: some View {
        Text(Money.format(amount, from: isFrom)).monospacedDigit()
    }
}

/// KPI tile for reports and client stats.
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .accentColor
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
                Text(title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.footnote.weight(.medium))
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let footnote {
                Text(footnote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct TelegramBadge: View {
    var body: some View {
        Image(systemName: "paperplane.circle.fill")
            .symbolRenderingMode(.multicolor)
            .foregroundStyle(.blue)
            .accessibilityLabel("Telegram подключён")
    }
}

/// Stock quantity pill, red when low.
struct QuantityBadge: View {
    let quantity: Int
    let unit: String
    let isLow: Bool

    var body: some View {
        Text("\(quantity) \(unit)")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isLow ? Color.red : Color.primary)
            .background((isLow ? Color.red : Color.secondary).opacity(isLow ? 0.15 : 0.12), in: .capsule)
            .accessibilityLabel(isLow ? "Мало: \(quantity) \(unit)" : "Остаток: \(quantity) \(unit)")
    }
}

/// Vertical icon-over-title label used by glass action buttons.
struct ActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(height: 24)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Signed money difference with color: green when zero, red when short, orange when over.
struct DifferenceText: View {
    let amount: Int

    var body: some View {
        Text(amount == 0 ? "Без расхождений" : Money.formatSigned(amount))
            .monospacedDigit()
            .foregroundStyle(amount == 0 ? Color.green : (amount < 0 ? Color.red : Color.orange))
    }
}
