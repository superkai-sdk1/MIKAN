import SwiftUI

/// «Расходники» of the completion sheet: rows prefilled from the norms of the visit's services, presence consumables
/// as «используется», «Добавить расходник» for anything else used, «Вернуть нормы» after changes.
struct CompleteConsumablesSection: View {
    /// All consumables of the warehouse (inactive included, so every norm resolves).
    let products: Remote<[Product]>
    /// The visit's norms (counted consumables), the steppers' starting values.
    let norms: [ServiceConsumable]
    /// Presence consumables the visit's services use.
    let presence: [Product]
    @Binding var usage: [Int: Int]
    /// Rows in order: the norms, then what staff added.
    @Binding var shown: [Int]
    let retry: () async -> Void

    @State private var showsPicker = false

    private var isEdited: Bool { VisitConsumption.isEdited(usage: usage, norms: norms) }

    var body: some View {
        Section {
            if let all = products.value {
                ForEach(shown, id: \.self) { id in
                    if let product = all.first(where: { $0.id == id }) {
                        ConsumableUsageRow(
                            product: product,
                            quantity: quantityBinding(id),
                            norm: norms.first { $0.productId == id }?.quantity
                        )
                    }
                }
                ForEach(presence) { product in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                            Text(ServiceLinkText.consumableStock(product))
                                .font(.caption)
                                .foregroundStyle(product.lowStock ? Color.orange : Color.secondary)
                        }
                        Spacer(minLength: 8)
                        StatusBadge(text: "используется", color: .secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if shown.isEmpty && presence.isEmpty {
                    Text("У услуг записи нет нормы расхода.")
                        .foregroundStyle(.secondary)
                }
                addButton(all)
                if isEdited && !norms.isEmpty {
                    Button("Вернуть нормы услуг", systemImage: "arrow.uturn.backward", action: resetToNorms)
                }
            } else if let failure = products.failure {
                Text(failure).foregroundStyle(.red)
                Button("Повторить") { Task { await retry() } }
            } else {
                ProgressView()
            }
        } header: {
            Text("Расходники")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        if isEdited {
            return "Спишется ровно указанное. Если на складе меньше, завершить запись не получится."
        }
        if norms.isEmpty {
            return "Отметьте расходники, если они ушли на процедуру, — они спишутся со склада."
        }
        return "Спишется по нормам услуг. Если чего-то не хватит, спишется остаток, а нехватку покажем после завершения."
    }

    private func addButton(_ all: [Product]) -> some View {
        Button("Добавить расходник", systemImage: "plus.circle.fill") { showsPicker = true }
            .sheet(isPresented: $showsPicker) {
                ServiceProductPicker(
                    kind: .consumable,
                    products: all.filter { !$0.isPresenceTracked },
                    selected: shown.filter { (usage[$0] ?? 0) > 0 },
                    title: "Расходники",
                    footer: "Отметьте, что ушло на процедуру; количество задаётся в строке. Расходники «есть / нет» не списываются.",
                    limit: ServiceLimits.maxConsumables
                ) { ids in
                    let next = VisitConsumption.applying(selection: ids, usage: usage, shown: shown, norms: norms)
                    withAnimation(.snappy) {
                        usage = next.usage
                        shown = next.shown
                    }
                }
            }
    }

    private func quantityBinding(_ id: Int) -> Binding<Int> {
        Binding(get: { usage[id] ?? 0 }, set: { usage[id] = $0 })
    }

    private func resetToNorms() {
        withAnimation(.snappy) {
            usage = VisitConsumption.usage(from: norms)
            shown = norms.map(\.productId)
        }
    }
}

/// One consumable used on the visit: stock, the norm and a stepper; orange when the stock is short.
private struct ConsumableUsageRow: View {
    let product: Product
    @Binding var quantity: Int
    /// Units the visit's norms ask for; `nil` for a consumable staff added.
    let norm: Int?

    /// Within the stock (the server refuses more), unless the norm already asks for more.
    private var range: ClosedRange<Int> { 0...max(product.quantity, quantity, norm ?? 0) }
    private var isShort: Bool { quantity > product.quantity }

    private var caption: String {
        if isShort { return "На складе только \(product.quantity) \(product.unitLabel)" }
        let stock = "На складе: \(product.quantity) \(product.unitLabel)"
        guard let norm else { return stock }
        return "\(stock) · норма \(norm)"
    }

    var body: some View {
        Stepper(value: $quantity, in: range) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(isShort ? Color.orange : (product.lowStock ? Color.red : Color.secondary))
                }
                Spacer(minLength: 8)
                Text("\(quantity)")
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .contentTransition(.numericText(value: Double(quantity)))
                    .animation(.snappy, value: quantity)
            }
        }
        .accessibilityValue("\(quantity) \(product.unitLabel)")
    }
}
