import SwiftUI

/// «+ Услуга»: popular services as tiles, search across all services, a custom service and the full catalog.
struct AddServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CartStore.self) private var cart
    @Environment(ReferenceStore.self) private var reference
    @Environment(APIClient.self) private var api

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
                        PopularServiceTile(service: service) { add(service) }
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
                        ServicePickRow(service: service) { add(service) }
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
                ServicePickRow(service: service) { add(service) }
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

    private func add(_ service: Service) {
        cart.add(service: service)
        addedCount += 1
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(service.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(Money.format(service.price, from: service.priceFrom))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(12)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.name), \(Money.format(service.price, from: service.priceFrom))")
        .accessibilityHint("Добавить в чек")
    }
}

private struct ServicePickRow: View {
    let service: Service
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(service.name).foregroundStyle(.primary)
                Spacer()
                Text(Money.format(service.price, from: service.priceFrom))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        // A list row, not a link: plain text colors instead of the accent tint.
        .tint(.primary)
    }
}

#if DEBUG
#Preview {
    AddServiceSheet()
        .previewEnvironment()
}
#endif
