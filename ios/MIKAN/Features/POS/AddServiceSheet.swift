import SwiftUI

/// Adds a catalog service or a custom one (name + price) to the cart.
struct AddServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CartStore.self) private var cart
    @Environment(ReferenceStore.self) private var reference

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
                                Button {
                                    cart.add(service: service)
                                    addedCount += 1
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(service.name).foregroundStyle(.primary)
                                        Spacer()
                                        Text(Money.format(service.price, from: service.priceFrom))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(.rect)
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

#if DEBUG
#Preview {
    AddServiceSheet()
        .previewEnvironment()
}
#endif
