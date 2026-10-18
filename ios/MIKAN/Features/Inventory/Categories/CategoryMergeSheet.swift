import SwiftUI

/// «Объединить с…»: picks the category the source's items move into; the source is deleted after the move.
struct CategoryMergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: CatalogCategory
    /// The other categories of the same scope.
    let targets: [CatalogCategory]
    let onMerge: (CatalogCategory) -> Void

    @State private var search = ""
    @State private var confirming: CatalogCategory?

    private var visibleTargets: [CatalogCategory] {
        let query = InventoryFilter.normalized(search)
        guard !query.isEmpty else { return targets }
        return targets.filter { InventoryFilter.normalized($0.name).contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visibleTargets) { target in
                        Button {
                            confirming = target
                        } label: {
                            LabeledContent(target.name, value: CategoryEditing.countText(target.itemCount, section: source.section))
                                .monospacedDigit()
                                .contentShape(.rect)
                        }
                        .tint(.primary)
                    }
                } footer: {
                    Text("Всё из «\(source.name)» перейдёт в выбранную категорию, а «\(source.name)» удалится.")
                }
            }
            .searchable(text: $search, prompt: "Найти категорию")
            .overlay {
                if visibleTargets.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Объединить «\(source.name)»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
            }
            .confirmationDialog(
                confirming.map { "Перенести в «\($0.name)»?" } ?? "",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                titleVisibility: .visible,
                presenting: confirming
            ) { target in
                Button("Объединить") {
                    onMerge(target)
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            } message: { target in
                Text(message(into: target))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func message(into target: CatalogCategory) -> String {
        let moving = source.itemCount > 0
            ? "Из «\(source.name)» в «\(target.name)»: \(CategoryEditing.countText(source.itemCount, section: source.section))."
            : "«\(source.name)» пустая."
        return "\(moving) Категория «\(source.name)» удалится."
    }
}
