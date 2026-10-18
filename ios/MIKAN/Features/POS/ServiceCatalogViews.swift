import SwiftUI

/// What the POS catalog shows: the warehouse sections that are sold.
enum POSCatalog: String, CaseIterable, Identifiable {
    case jewelry
    case services
    case goods

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jewelry: "Украшения"
        case .services: "Услуги"
        case .goods: "Товары"
        }
    }

    var searchPrompt: String {
        switch self {
        case .jewelry: "Поиск украшений"
        case .services: "Поиск услуг"
        case .goods: "Поиск товаров"
        }
    }

    func sectionTitle(isSearching: Bool) -> String {
        switch self {
        case .jewelry: isSearching ? "Найдено в каталоге" : "Добавить украшение"
        case .services: isSearching ? "Найдено в услугах" : "Добавить услугу"
        case .goods: isSearching ? "Найдено в товарах" : "Добавить товар"
        }
    }
}

/// Filtering, grouping and hints of the POS service catalog (pure, no UI state).
nonisolated enum POSServiceCatalog {
    /// Title of the ungrouped rest of a category that has named groups; that section goes last.
    static let ungroupedTitle = "Другое"

    /// One grid section: a group of one category.
    struct GridSection: Identifiable, Equatable, Sendable {
        let category: ServiceCategory
        /// Group title («Другое» for the ungrouped rest); `nil` when the category has no named groups.
        let group: String?
        let isFirstInCategory: Bool
        let services: [Service]

        var id: String { "\(category.rawValue)|\(group ?? "")" }

        /// Header lines. The category title opens each category when several are shown; the group title
        /// follows unless it just repeats that category title (group «Тату» inside «Тату»).
        func headers(showsCategories: Bool) -> (category: String?, group: String?) {
            let categoryTitle = showsCategories && isFirstInCategory ? category.title : nil
            let groupTitle = categoryTitle != nil && group == category.title ? nil : group
            return (categoryTitle, groupTitle)
        }
    }

    /// Categories that have at least one of `services`, in the standard order.
    static func categories(of services: [Service]) -> [ServiceCategory] {
        ServiceCategory.allCases.filter { category in services.contains { $0.category == category } }
    }

    /// Services of `category` (all when `nil`) whose name, group, description or variants match `query`.
    static func filter(_ services: [Service], category: ServiceCategory?, query: String) -> [Service] {
        let needle = query.trimmed.lowercased()
        return services.filter { service in
            guard category == nil || service.category == category else { return false }
            guard !needle.isEmpty else { return true }
            let haystack = ([service.name, service.group, service.description] + service.variants.map(\.name))
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return haystack.contains(needle)
        }
    }

    /// Sections by category (tattoo, piercing, other), then by group in catalog order (`sort`, name);
    /// the ungrouped rest of a category goes last as «Другое» — the same order as the services list.
    static func sections(_ services: [Service]) -> [GridSection] {
        let ordered = services.sorted { ($0.sort, $0.name, $0.id) < ($1.sort, $1.name, $1.id) }
        return ServiceCategory.allCases.flatMap { category in
            sections(of: category, ordered.filter { $0.category == category })
        }
    }

    private static func sections(of category: ServiceCategory, _ items: [Service]) -> [GridSection] {
        let hasNamedGroups = items.contains { $0.group.nonEmpty != nil }
        let firstSeen = items.map(\.groupTitle).reduce(into: [String]()) { titles, title in
            if !titles.contains(title) { titles.append(title) }
        }
        let titles = firstSeen.filter { $0 != ungroupedTitle } + firstSeen.filter { $0 == ungroupedTitle }
        return titles.enumerated().map { index, title in
            GridSection(
                category: category,
                group: hasNamedGroups ? title : nil,
                isFirstInCategory: index == 0,
                services: items.filter { $0.groupTitle == title }
            )
        }
    }

    /// Splits tiles into fixed-width rows, so a `List` lays out (and lazily loads) the grid row by row.
    static func rows(_ services: [Service], columns: Int) -> [[Service]] {
        guard columns > 0 else { return [] }
        return stride(from: 0, to: services.count, by: columns).map { start in
            Array(services[start..<min(start + columns, services.count)])
        }
    }

    /// Shown after adding a service whose final price is set per visit.
    static func priceHint(for service: Service, variant: ServiceVariant?) -> String? {
        guard variant == nil, service.hasVariablePrice else { return nil }
        return "Добавлено по \(Money.format(service.price)) — итоговую цену можно изменить в чеке"
    }
}

/// «Услуги» rows of the receipt catalog `List`: category chips, then section headers and rows of service tiles.
/// The owner loads the services (`ReferenceStore.ensureServices`) and reports through `state`.
struct POSServiceCatalogSection: View {
    @Environment(CartStore.self) private var cart
    @Environment(ReferenceStore.self) private var reference

    let state: Remote<Void>
    let search: String
    let columns: Int
    let spacing: CGFloat
    let load: () async -> Void
    /// Called after a service was added, with a price hint for variable-price services.
    let onAdd: (_ hint: String?) -> Void

    @State private var category: ServiceCategory?

    private var services: [Service] { reference.activeServices }

    private var filtered: [Service] {
        // A category that vanished after a refresh no longer filters anything out.
        let selected = category.flatMap { POSServiceCatalog.categories(of: services).contains($0) ? $0 : nil }
        return POSServiceCatalog.filter(services, category: selected, query: search)
    }

    var body: some View {
        let categories = POSServiceCatalog.categories(of: services)
        if categories.count > 1 {
            CategoryChips(categories: categories.map(\.title), selection: categoryTitle(among: categories))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        if state.value != nil || !services.isEmpty {
            let sections = POSServiceCatalog.sections(filtered)
            if sections.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                let showsCategories = Set(sections.map(\.category)).count > 1
                ForEach(sections) { section in
                    let headers = section.headers(showsCategories: showsCategories)
                    if headers.category != nil || headers.group != nil {
                        ServiceSectionHeader(category: headers.category, group: headers.group)
                            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(POSServiceCatalog.rows(section.services, columns: columns), id: \.self) { row in
                        tileRow(row)
                            .listRowInsets(EdgeInsets(top: spacing / 2, leading: 0, bottom: spacing / 2, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        } else if let failure = state.failure {
            ErrorStateView(message: failure, retry: load)
                .listRowBackground(Color.clear)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
                .listRowBackground(Color.clear)
        }
    }

    private func tileRow(_ row: [Service]) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(row) { service in
                POSServiceTile(service: service, inCart: cart.quantity(ofService: service.id)) { variant in
                    add(service, variant: variant)
                }
                .frame(maxWidth: .infinity)
            }
            ForEach(row.count..<columns, id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.trimmed.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView(
                "Нет услуг",
                systemImage: "sparkles",
                description: Text("Добавьте услуги в разделе «Склад» → «Услуги». Свою услугу можно добавить кнопкой «Услуга».")
            )
        }
    }

    private func categoryTitle(among categories: [ServiceCategory]) -> Binding<String?> {
        Binding(
            get: { category?.title },
            set: { title in category = categories.first { $0.title == title } }
        )
    }

    private func add(_ service: Service, variant: ServiceVariant?) {
        withAnimation(.snappy) { cart.add(service: service, variant: variant) }
        onAdd(POSServiceCatalog.priceHint(for: service, variant: variant))
    }
}

/// Category and/or group title above a block of service tiles.
private struct ServiceSectionHeader: View {
    let category: String?
    let group: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let category {
                Text(category)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            if let group {
                Text(group)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Service tile in the POS catalog. Tap adds it; a service with variants asks which one first.
struct POSServiceTile: View {
    let service: Service
    let inCart: Int
    let onAdd: (ServiceVariant?) -> Void

    @State private var choosesVariant = false

    var body: some View {
        Button {
            if service.variants.isEmpty { onAdd(nil) } else { choosesVariant = true }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ServiceSquareCover(service: service)
                    .overlay(alignment: .topTrailing) { cartBadge }
                    .overlay(alignment: .bottomLeading) { variantsBadge }
                Text(service.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                Text(service.priceText)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
            .animation(.snappy, value: inCart)
        }
        .buttonStyle(.plain)
        .serviceVariantDialog(for: service, isPresented: $choosesVariant) { onAdd($0) }
        .accessibilityLabel("\(service.name), \(service.priceText)")
        .accessibilityHint(service.variants.isEmpty ? "Добавить в чек" : "Выбрать вариант и добавить в чек")
        .accessibilityValue(inCart > 0 ? "В чеке: \(inCart)" : "")
    }

    @ViewBuilder
    private var cartBadge: some View {
        if inCart > 0 {
            Text("\(inCart)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 26, minHeight: 26)
                .background(Color.accentColor, in: .circle)
                .padding(6)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var variantsBadge: some View {
        if !service.variants.isEmpty {
            Text(Plural.count(service.variants.count, one: "вариант", few: "варианта", many: "вариантов"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: .capsule)
                .padding(6)
        }
    }
}

/// Square service picture on white (the schematic covers are drawn on white); category symbol when there is none.
struct ServiceSquareCover: View {
    @Environment(APIClient.self) private var api
    let service: Service
    var cornerRadius: CGFloat = 14

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { picture }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var picture: some View {
        if let url = api.mediaURL(for: service.coverPath) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    ZStack {
                        Color.white
                        image.resizable().scaledToFill()
                    }
                case .failure:
                    placeholder(symbol: "photo.badge.exclamationmark")
                default:
                    Color.white
                }
            }
        } else {
            placeholder(symbol: service.category.symbol)
        }
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Asks which variant of `service` to add; anchored to the view it is attached to.
    func serviceVariantDialog(
        for service: Service,
        isPresented: Binding<Bool>,
        onPick: @escaping (ServiceVariant) -> Void
    ) -> some View {
        confirmationDialog(service.name, isPresented: isPresented, titleVisibility: .visible) {
            ForEach(Array(service.variants.enumerated()), id: \.offset) { _, variant in
                Button("\(variant.name) — \(Money.format(variant.price))") { onPick(variant) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выберите вариант")
        }
    }
}

/// Short message shown above the cart bar after adding something (e.g. a variable-price service).
struct CatalogHint: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

private struct CatalogHintOverlay: ViewModifier {
    @Binding var hint: CatalogHint?

    private static let visibleFor: Duration = .seconds(3)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let hint {
                    Label(hint.text, systemImage: "pencil.and.list.clipboard")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .onTapGesture { self.hint = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(hint.id)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hint)
            .task(id: hint?.id) {
                guard let hint else { return }
                AccessibilityNotification.Announcement(hint.text).post()
                do {
                    try await Task.sleep(for: Self.visibleFor)
                } catch {
                    return // replaced by a newer hint or the view went away
                }
                if self.hint?.id == hint.id { self.hint = nil }
            }
    }
}

extension View {
    /// Shows `hint` at the bottom for a few seconds (tap hides it sooner).
    func catalogHint(_ hint: Binding<CatalogHint?>) -> some View {
        modifier(CatalogHintOverlay(hint: hint))
    }
}

#if DEBUG
#Preview("Услуги") {
    let state = PreviewData.appState()
    state.reference.replaceServices(PreviewData.services)
    return List {
        Section("Добавить услугу") {
            POSServiceCatalogSection(state: Remote(()), search: "", columns: 2, spacing: 12, load: {}) { _ in }
        }
    }
    .appEnvironment(state)
}
#endif
