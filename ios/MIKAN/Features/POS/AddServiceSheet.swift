import SwiftUI

/// Adds a custom service (name + price) or a catalog one to the cart.
struct AddServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CartStore.self) private var cart
    @Environment(ReferenceStore.self) private var reference

    /// Called after a catalog service was added, with a price hint for variable-price services.
    var onAdd: (_ hint: String?) -> Void = { _ in }

    @State private var customName = ""
    @State private var customPrice = 0
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var addedCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Название услуги", text: $customName)
                    NumberField.money("Цена", value: $customPrice)
                    Button("Добавить в чек", systemImage: "plus.circle.fill") {
                        cart.addCustomService(name: customName, price: customPrice)
                        addedCount += 1
                        dismiss()
                    }
                    .disabled(customName.trimmed.isEmpty)
                } header: {
                    Text("Своя услуга")
                }
                ForEach(ServiceCategory.allCases) { category in
                    let services = reference.activeServices.filter { $0.category == category }
                    if !services.isEmpty {
                        Section(category.title) {
                            ForEach(services) { service in
                                ServiceRowButton(service: service) { variant in
                                    add(service, variant: variant)
                                }
                            }
                        }
                    }
                }
                if let loadError {
                    Section {
                        Text(loadError).foregroundStyle(.red)
                        Button("Повторить") { Task { await load() } }
                    }
                } else if isLoading && reference.services.isEmpty {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }
            }
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
        .presentationDetents([.medium, .large])
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
    }
}

/// Catalog service row with its cover; asks which variant first when the service has them.
private struct ServiceRowButton: View {
    let service: Service
    let onAdd: (ServiceVariant?) -> Void

    @State private var choosesVariant = false

    var body: some View {
        Button {
            if service.variants.isEmpty { onAdd(nil) } else { choosesVariant = true }
        } label: {
            HStack(spacing: 12) {
                ServiceThumbnail(service: service, size: 44)
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
