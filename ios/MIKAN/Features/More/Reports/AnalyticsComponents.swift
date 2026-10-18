import SwiftUI

/// Building blocks shared by the analytics cards.

/// Colors of chart slices and bars, in slice order: the brand mandarin first.
enum AnalyticsPalette {
    static let colors: [Color] = [Theme.mandarin, .blue, .green, .purple, .teal, .pink, .indigo, .gray]

    static func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}

extension AnalyticsDelta.Tone {
    var color: Color {
        switch self {
        case .good: .green
        case .bad: .red
        case .neutral: .secondary
        }
    }
}

/// Card header: icon and title, optional caption under it.
struct AnalyticsCardTitle: View {
    let title: String
    let systemImage: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(AnalyticsTitleLabelStyle())
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct AnalyticsTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(Color.accentColor)
            configuration.title
        }
    }
}

/// «Title ……… 1 200 ₽» with an optional detail line.
struct AnalyticsMoneyRow: View {
    let title: String
    let amount: Int
    var detail: String?
    var isEmphasized = false
    var tint: Color?

    var body: some View {
        AnalyticsValueRow(title: title, value: Money.format(amount), detail: detail, isEmphasized: isEmphasized, tint: tint)
    }
}

/// «Title ……… value» with an optional detail line.
struct AnalyticsValueRow: View {
    let title: String
    let value: String
    var detail: String?
    var isEmphasized = false
    var tint: Color?

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
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
        }
        .font(.subheadline.weight(isEmphasized ? .semibold : .regular))
        .accessibilityElement(children: .combine)
    }
}

/// A part of a whole with its amount, share and a bar.
struct AnalyticsShareRow: View {
    let title: String
    let amount: Int
    let share: Double
    var detail: String?
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                MoneyText(amount).fontWeight(.semibold)
                Text(share.formatted(.percent.precision(.fractionLength(0)).locale(.app)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .font(.subheadline)
            ProgressView(value: min(max(share, 0), 1))
                .tint(color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A note under a card: why a number may be incomplete, what it does not include.
struct AnalyticsHint: View {
    let text: String
    var systemImage = "info.circle"
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A ranked list showing the first rows, with «Показать все» for the rest.
struct AnalyticsTopList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var collapsedCount = 5
    @ViewBuilder let row: (Int, Item) -> Row
    @State private var isExpanded = false

    private var visible: [(offset: Int, element: Item)] {
        Array(items.enumerated().prefix(isExpanded ? items.count : collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visible, id: \.element.id) { entry in
                row(entry.offset, entry.element)
            }
            if items.count > collapsedCount {
                Button(isExpanded ? "Свернуть" : "Показать все (\(items.count))") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }
}

/// Position badge of a ranked row.
struct AnalyticsRank: View {
    let index: Int

    var body: some View {
        Text("\(index + 1)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.accentColor)
            .monospacedDigit()
            .frame(width: 22, alignment: .leading)
    }
}
