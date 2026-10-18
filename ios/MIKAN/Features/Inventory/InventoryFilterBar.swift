import SwiftUI

/// Pinned bar over the warehouse: the section switcher and, for product sections, «Мало», the facet menu and the
/// chips of chosen facets.
struct InventoryFilterBar: View {
    @Bindable var model: InventoryModel
    /// Category names in the registry order.
    let categoryOptions: [String]
    let onSelect: (CatalogSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Раздел склада", selection: sectionBinding) {
                ForEach(CatalogSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            if model.kind != nil {
                HStack(spacing: 8) {
                    Toggle(isOn: $model.filter.lowOnly.animation(.snappy)) {
                        Label("Мало", systemImage: "exclamationmark.triangle")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.glass)
                    .accessibilityHint(lowHint)
                    facetMenu
                    if model.filter.facetCount > 0 {
                        activeFacets
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var sectionBinding: Binding<CatalogSection> {
        Binding(get: { model.section }, set: { onSelect($0) })
    }

    private var lowHint: String {
        model.kind == .consumable
            ? "Показать только то, что заканчивается"
            : "Показать только позиции с низким остатком"
    }

    private var facetMenu: some View {
        Menu {
            facetPicker("Категория", options: categoryOptions, selection: $model.filter.category)
            if !model.materialOptions.isEmpty {
                facetPicker("Материал", options: model.materialOptions, selection: $model.filter.material)
            }
            if !model.sizeOptions.isEmpty {
                facetPicker(model.kind == .goods ? "Размер / объём" : "Размер", options: model.sizeOptions, selection: $model.filter.size)
            }
            if model.offersPresenceFilter {
                Picker("Наличие", selection: $model.filter.presence.animation(.snappy)) {
                    Text("Все").tag(PresenceStatus?.none)
                    ForEach(PresenceStatus.allCases) { status in
                        Label(status.title, systemImage: status.symbol).tag(PresenceStatus?.some(status))
                    }
                }
                .pickerStyle(.menu)
            }
            if model.filter.facetCount > 0 {
                Divider()
                Button("Сбросить фильтры", systemImage: "xmark.circle", role: .destructive) { resetFacets() }
            }
        } label: {
            Label(
                "Фильтры",
                systemImage: model.filter.facetCount > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .accessibilityValue(model.filter.facetCount > 0 ? "Выбрано: \(model.filter.facetCount)" : "")
    }

    @ViewBuilder
    private func facetPicker(_ title: String, options: [String], selection: Binding<String?>) -> some View {
        Picker(title, selection: selection.animation(.snappy)) {
            Text("Все").tag(String?.none)
            ForEach(options, id: \.self) { option in
                Text(option).tag(String?.some(option))
            }
        }
        .pickerStyle(.menu)
        .disabled(options.isEmpty)
    }

    private var activeFacets: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                facetChip("Категория", value: model.filter.category) { model.filter.category = nil }
                facetChip("Материал", value: model.filter.material) { model.filter.material = nil }
                facetChip("Размер", value: model.filter.size) { model.filter.size = nil }
                facetChip("Наличие", value: model.filter.presence?.title) { model.filter.presence = nil }
                if model.filter.facetCount > 1 {
                    Button("Сбросить", action: resetFacets)
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func facetChip(_ title: String, value: String?, remove: @escaping () -> Void) -> some View {
        if let value = value.nonEmpty {
            Button {
                withAnimation(.snappy) { remove() }
            } label: {
                HStack(spacing: 4) {
                    Text(value).lineLimit(1)
                    Image(systemName: "xmark").imageScale(.small)
                }
                .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityLabel("\(title): \(value)")
            .accessibilityHint("Убрать фильтр")
        }
    }

    private func resetFacets() {
        withAnimation(.snappy) {
            model.filter = model.filter.withoutFacets
        }
    }
}
