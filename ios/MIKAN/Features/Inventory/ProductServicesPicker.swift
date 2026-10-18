import SwiftUI

/// Multi-select of the catalog services (piercing zones) a piece of jewelry suits; piercing first.
struct ProductServicesPicker: View {
    @Environment(ReferenceStore.self) private var reference
    @Binding var draft: ProductDraft

    @State private var isLoading = false
    @State private var loadError: String?

    private var options: [Service] { ProductServiceOptions.options(reference.services, selected: draft.serviceIds) }

    var body: some View {
        List {
            ForEach(ProductServiceOptions.categoryOrder, id: \.self) { category in
                let services = options.filter { $0.category == category }
                if !services.isEmpty {
                    Section(category.title) {
                        ForEach(services) { service in
                            row(service)
                        }
                    }
                }
            }
        }
        .overlay {
            if options.isEmpty {
                if let loadError {
                    ErrorStateView(message: loadError) { await load(force: true) }
                } else if isLoading {
                    ProgressView().controlSize(.large)
                } else {
                    ContentUnavailableView(
                        "Услуг пока нет",
                        systemImage: "sparkle",
                        description: Text("Добавьте услуги пирсинга на складе в разделе «Услуги».")
                    )
                }
            }
        }
        .navigationTitle("Подходящие услуги")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !draft.serviceIds.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") { draft.serviceIds = [] }
                }
            }
        }
        .task { await load(force: false) }
    }

    private func row(_ service: Service) -> some View {
        let isSelected = draft.serviceIds.contains(service.id)
        return Button {
            draft = draft.togglingService(service.id)
        } label: {
            HStack(spacing: 12) {
                ServiceThumbnail(service: service, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name).foregroundStyle(.primary)
                    if let group = service.group.nonEmpty {
                        Text(group).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !service.active {
                    StatusBadge(text: "Скрыта", color: .gray)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(!isSelected && draft.serviceIds.count >= ProductLimits.maxServices)
    }

    private func load(force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await reference.ensureServices(force: force)
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.userMessage
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var draft = ProductDraft(product: PreviewData.labret)
    NavigationStack {
        ProductServicesPicker(draft: $draft)
    }
    .previewEnvironment()
}
#endif
