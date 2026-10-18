import Foundation

/// Pure rules of the categories editor: name checks like the server's, reordering and texts.
nonisolated enum CategoryEditing {
    static let maxNameLength = 100

    /// The scopes a section's categories live in: one for products, one per service category for services.
    static func scopes(of section: CatalogSection) -> [ServiceCategory?] {
        section == .service ? ServiceCategory.allCases.map(Optional.some) : [nil]
    }

    /// Why the name cannot be saved in the scope, or `nil`. Names compare trimmed, case- and «ё»-insensitive;
    /// `excluding` is the category being renamed.
    static func nameProblem(_ name: String, in scope: [CatalogCategory], excluding id: Int? = nil) -> String? {
        guard let value = name.nonEmpty else { return "Укажите название категории." }
        if value.count > maxNameLength { return "Название — не длиннее \(maxNameLength) символов." }
        let key = InventoryFilter.normalized(value)
        if let twin = scope.first(where: { $0.id != id && InventoryFilter.normalized($0.name) == key }) {
            return "Категория «\(twin.name)» уже есть."
        }
        return nil
    }

    /// The scope after moving rows like `List.onMove`, with positions renumbered from 0.
    static func reordered(_ scope: [CatalogCategory], fromOffsets source: IndexSet, toOffset destination: Int) -> [CatalogCategory] {
        let moving = source.sorted().filter { scope.indices.contains($0) }.map { scope[$0] }
        var rest = scope.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(0, insertAt), rest.count))
        return rest.enumerated().map { index, category in
            var copy = category
            copy.position = index
            return copy
        }
    }

    /// The section's list with one scope replaced (other scopes and sections untouched).
    static func replacingScope(
        in all: [CatalogCategory],
        section: CatalogSection,
        serviceCategory: ServiceCategory?,
        with scope: [CatalogCategory]
    ) -> [CatalogCategory] {
        all.filter { !($0.section == section && $0.serviceCategory == serviceCategory) } + scope
    }

    /// Replaces or appends one category.
    static func upserting(_ category: CatalogCategory, in all: [CatalogCategory]) -> [CatalogCategory] {
        guard all.contains(where: { $0.id == category.id }) else { return all + [category] }
        return all.map { $0.id == category.id ? category : $0 }
    }

    /// «12 позиций», «3 услуги», «Пусто».
    static func countText(_ count: Int, section: CatalogSection) -> String {
        guard count > 0 else { return "Пусто" }
        return section == .service
            ? Plural.count(count, one: "услуга", few: "услуги", many: "услуг")
            : Plural.count(count, one: "позиция", few: "позиции", many: "позиций")
    }
}
