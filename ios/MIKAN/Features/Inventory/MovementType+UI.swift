import SwiftUI

extension MovementType {
    var title: String {
        switch self {
        case .receipt: "Приход"
        case .sale: "Продажа"
        case .returned: "Возврат"
        case .writeoff: "Списание"
        case .usage: "Расход"
        case .adjustment: "Инвентаризация"
        }
    }

    /// Short label for segmented pickers.
    var shortTitle: String {
        switch self {
        case .adjustment: "Пересчёт"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .receipt: "arrow.down.to.line"
        case .sale: "cart"
        case .returned: "arrow.uturn.backward"
        case .writeoff: "trash"
        case .usage: "drop"
        case .adjustment: "list.number"
        }
    }

    var hint: String {
        switch self {
        case .receipt: "Сколько единиц поступило на склад."
        case .writeoff: "Брак, потеря, истёк срок — сколько единиц списать."
        case .usage: "Сколько ушло на процедуры (не через завершение записи)."
        case .adjustment: "Пересчитайте остаток и введите фактическое количество."
        case .sale, .returned: ""
        }
    }
}

/// Stock movement row: type, signed delta, resulting stock of the size, author and note.
/// The global list names the product and size («Лабрет — 8 мм»); a product's own list shows the size as a badge.
struct MovementRow: View {
    let movement: StockMovement
    var showsProduct = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: movement.type.symbol)
                .font(.body)
                .foregroundStyle(movement.delta >= 0 ? Color.green : Color.orange)
                .frame(width: 28, height: 28)
                .background((movement.delta >= 0 ? Color.green : Color.orange).opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(showsProduct ? movement.displayName : movement.type.title)
                        .font(.subheadline.weight(.semibold))
                    if !showsProduct, let size = movement.variantName.nonEmpty {
                        StatusBadge(text: size, color: .secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = movement.note.nonEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(movement.delta > 0 ? "+\(movement.delta)" : "\(movement.delta)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(movement.delta >= 0 ? Color.green : Color.primary)
                Text("→ \(movement.quantityAfter)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsProduct { parts.append(movement.type.title) }
        parts.append(DateText.dateTime(movement.createdAt))
        if let employee = movement.employee { parts.append(employee.name) }
        return parts.joined(separator: " · ")
    }
}
