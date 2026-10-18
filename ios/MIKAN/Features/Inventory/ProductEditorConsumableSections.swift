import SwiftUI

// Consumable parts of the product editor: how it is tracked, and the services that use it.

/// «Учёт на складе»: counted in units (stock and minimum) or only «есть / заканчивается / нет» (the status).
struct ConsumableStockSection: View {
    @Binding var draft: ProductDraft

    var body: some View {
        Section {
            Picker("Учёт", selection: $draft.stockMode.animation()) {
                ForEach(StockMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if draft.isPresenceTracked {
                PresenceStatusPicker(selection: draft.presenceStatus) { status in
                    draft.presenceStatus = status
                }
                .listRowSeparator(.hidden, edges: .top)
            } else if let size = draft.sizes.first, !draft.hasSeveralSizes {
                if size.isNew {
                    NumberField.integer("Начальный остаток", value: firstSize(\.initialQuantity), unit: draft.unitLabel)
                } else {
                    LabeledContent("На складе", value: InventoryText.quantity(size.quantity, unit: draft.unitLabel))
                        .monospacedDigit()
                }
                NumberField.integer("Минимальный остаток", value: firstSize(\.minQuantity), unit: draft.unitLabel)
            }
        } header: {
            Text("Учёт на складе")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        guard draft.isPresenceTracked else {
            return "Остаток считается в единицах: приход, расход по нормам услуг при завершении записи, списания и ревизии."
        }
        let base = "Без количества: отмечайте «есть», «заканчивается» или «нет» — здесь, в карточке, свайпом в списке склада или в ревизии. При завершении записи не списывается."
        guard let stock = draft.sizes.first?.quantity, stock > 0, !draft.isNew else { return base }
        return base + " Остаток \(InventoryText.quantity(stock, unit: draft.unitLabel)) сохранится и вернётся, если снова считать количество."
    }

    private func firstSize(_ keyPath: WritableKeyPath<SizeDraft, Int>) -> Binding<Int> {
        Binding(
            get: { draft.sizes.first?[keyPath: keyPath] ?? 0 },
            set: { value in
                guard !draft.sizes.isEmpty else { return }
                draft.sizes[0][keyPath: keyPath] = value
            }
        )
    }
}

/// «Используется в услугах»: the consumption norms of the services, read-only (they are edited in the service card).
struct ConsumableUsageSection: View {
    @Environment(ReferenceStore.self) private var reference
    let draft: ProductDraft

    var body: some View {
        Section {
            if let productId = draft.productId {
                let entries = ConsumableUsage.entries(for: productId, in: reference.services)
                if entries.isEmpty {
                    Text("Ни в одной услуге пока нет нормы с этим расходником.")
                        .foregroundStyle(.secondary)
                } else {
                    ConsumableUsageList(entries: entries, unit: draft.unitLabel, isPresence: draft.isPresenceTracked)
                }
            } else {
                Text("После сохранения добавьте расходник в нормы услуг.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Используется в услугах")
        } footer: {
            Text(ConsumableUsage.hint(isPresence: draft.isPresenceTracked))
        }
    }
}
