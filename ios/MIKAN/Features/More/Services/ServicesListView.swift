import SwiftUI

struct ServicesListView: View {
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference
    @State private var services = Remote<[Service]>()
    @State private var editing: ServiceEditTarget?

    var body: some View {
        List {
            ForEach(ServiceCategory.allCases) { category in
                let items = (services.value ?? []).filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { service in
                            Button {
                                editing = .existing(service)
                            } label: {
                                ServiceRow(service: service)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            RemoteStateOverlay(remote: services, retry: load) {
                ContentUnavailableView {
                    Label("Услуг пока нет", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Добавьте услуги с ценами и длительностью — они нужны для записи, кассы и ответов бота.")
                } actions: {
                    Button("Добавить услугу") { editing = .new }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(services)
        .navigationTitle("Услуги")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Новая услуга", systemImage: "plus") { editing = .new }
            }
        }
        .sheet(item: $editing) { target in
            ServiceEditorView(service: target.service, nextSort: (services.value?.map(\.sort).max() ?? -1) + 1) { saved in
                services.upsert(saved)
                let sorted = (services.value ?? []).sorted { ($0.sort, $0.name) < ($1.sort, $1.name) }
                services.set(sorted)
                reference.replaceServices(sorted)
            }
        }
    }

    private func load() async {
        await services.load { try await api.services(includeInactive: true) }
        if let value = services.value { reference.replaceServices(value) }
    }
}

enum ServiceEditTarget: Identifiable {
    case new
    case existing(Service)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let service): "service-\(service.id)"
        }
    }

    var service: Service? {
        if case .existing(let service) = self { return service }
        return nil
    }
}

private struct ServiceRow: View {
    let service: Service

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(service.name).font(.headline).foregroundStyle(.primary)
                    if !service.active {
                        StatusBadge(text: "Скрыта", color: .gray)
                    }
                }
                Text(DateText.duration(minutes: service.durationMin))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(service.price, from: service.priceFrom))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .contentShape(.rect)
        .opacity(service.active ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ServicesListView()
    }
    .previewEnvironment()
}
#endif
