import SwiftUI

/// Picks a catalog service (grouped by category), or none.
struct ServicePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReferenceStore.self) private var reference
    let selectedId: Int?
    var allowsNone = true
    let onSelect: (Service?) -> Void

    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if allowsNone {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    row(title: "Без услуги", subtitle: "Только описание", isSelected: selectedId == nil)
                }
            }
            ForEach(ServiceCategory.allCases) { category in
                let services = reference.activeServices.filter { $0.category == category }
                if !services.isEmpty {
                    Section(category.title) {
                        ForEach(services) { service in
                            Button {
                                onSelect(service)
                                dismiss()
                            } label: {
                                row(
                                    title: service.name,
                                    subtitle: "\(Money.format(service.price, from: service.priceFrom)) · \(DateText.duration(minutes: service.durationMin))",
                                    isSelected: service.id == selectedId
                                )
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if let loadError {
                ErrorStateView(message: loadError) { await load() }
            } else if isLoading && reference.services.isEmpty {
                ProgressView()
            } else if reference.activeServices.isEmpty {
                ContentUnavailableView(
                    "Нет услуг",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Добавьте услуги в разделе «Ещё → Услуги».")
                )
            }
        }
        .navigationTitle("Услуга")
        .task { await load() }
    }

    private func row(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(.rect)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    NavigationStack {
        ServicePickerView(selectedId: nil) { _ in }
    }
    .previewEnvironment()
}
#endif
