import SwiftUI

/// «+ Услуга»: popular services as tiles, search across all services, a custom service and the full catalog.
/// A service with variants asks which one first.
struct AddServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CartStore.self) private var cart
    @Environment(ReferenceStore.self) private var reference
    @Environment(APIClient.self) private var api

    /// Called after a catalog service was added, with a price hint for variable-price services.
    var onAdd: (_ hint: String?) -> Void = { _ in }

    @State private var query = ""
    @State private var topServices: [TopService] = []
    @State private var customName = ""
    @State private var customPrice = 0
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var addedCount = 0

    private var popular: [Service] { ServicePicking.popular(services: reference.services, top: topServices) }
    private var results: [Service] { ServicePicking.search(reference.services, query: query) }
    private var isSearching: Bool { !query.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    searchResults
                } else {
                    browse
                }
                statusSection
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск по всем услугам")
            .navigationTitle("Добавить услугу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", role: .close) { dismiss() }
                }
            }
            .task { await load() }
            .sensoryFeedback(.success, trigger: addedCount)
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var browse: some View {
        if !popular.isEmpty {
            Section("Популярные") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(popular) { service in
                        PopularServiceTile(service: service) { add(service, variant: $0) }
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }
        }
        Section("Своя услуга") {
            TextField("Название услуги", text: $customName)
            NumberField.money("Цена", value: $customPrice)
            Button("Добавить в чек", systemImage: "plus.circle.fill") {
                cart.addCustomService(name: customName, price: customPrice)
                addedCount += 1
                dismiss()
            }
            .disabled(customName.trimmed.isEmpty)
        }
        ForEach(ServiceCategory.allCases) { category in
            let services = ServicePicking.catalogOrder(reference.activeServices.filter { $0.category == category })
            if !services.isEmpty {
                Section(category.title) {
                    ForEach(services) { service in
                        ServicePickRow(service: service) { add(service, variant: $0) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        Section {
            if results.isEmpty {
                Text("Ничего не найдено")
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { service in
                ServicePickRow(service: service) { add(service, variant: $0) }
            }
            Button {
                customName = query.trimmed
                query = ""
            } label: {
                Label("Добавить «\(query.trimmed)» как свою услугу", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let loadError {
            Section {
                Text(loadError).foregroundStyle(.red)
                Button("Повторить") { Task { await load() } }
            }
        } else if isLoading && reference.services.isEmpty {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private func add(_ service: Service, variant: ServiceVariant?) {
        cart.add(service: service, variant: variant)
        addedCount += 1
        onAdd(POSServiceCatalog.priceHint(for: service, variant: variant))
        dismiss()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await reference.ensureServices()
            loadError = nil
        } catch {
            loadError = error.userMessage
        }
        // Popularity is a nice-to-have ranking: without the report the catalog order is used instead.
        let to = Date.now
        let from = Calendar.app.date(byAdding: .day, value: -ServicePicking.popularityWindowDays, to: to) ?? to
        topServices = (try? await api.reportSummary(from: from, to: to).topServices) ?? []
    }
}

private struct PopularServiceTile: View {
    let service: Service
    let onAdd: (ServiceVariant?) -> Void

    @State private var choosesVariant = false

    var body: some View {
        Button {
            if service.variants.isEmpty { onAdd(nil) } else { choosesVariant = true }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ServiceThumbnail(service: service, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text(service.priceText)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(10)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .serviceVariantDialog(for: service, isPresented: $choosesVariant) { onAdd($0) }
        .accessibilityLabel("\(service.name), \(service.priceText)")
        .accessibilityHint(service.variants.isEmpty ? "Добавить в чек" : "Выбрать вариант и добавить в чек")
    }
}

private struct ServicePickRow: View {
    let service: Service
    let onAdd: (ServiceVariant?) -> Void

    @State private var choosesVariant = false

    var body: some View {
        Button {
            if service.variants.isEmpty { onAdd(nil) } else { choosesVariant = true }
        } label: {
            HStack(spacing: 12) {
                ServiceThumbnail(service: service, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name).foregroundStyle(.primary)
                    if !service.variants.isEmpty {
                        Text(Plural.count(service.variants.count, one: "вариант", few: "варианта", many: "вариантов"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(service.priceText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .contentShape(.rect)
        }
        // A list row, not a link: plain text colors instead of the accent tint.
        .tint(.primary)
        .serviceVariantDialog(for: service, isPresented: $choosesVariant) { onAdd($0) }
        .accessibilityHint(service.variants.isEmpty ? "Добавить в чек" : "Выбрать вариант и добавить в чек")
    }
}

#if DEBUG
#Preview {
    AddServiceSheet()
        .previewEnvironment()
}
#endif
