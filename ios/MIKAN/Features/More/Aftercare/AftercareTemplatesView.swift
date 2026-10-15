import SwiftUI

struct AftercareTemplatesView: View {
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference
    @State private var templates = Remote<[AftercareTemplate]>()
    @State private var editing: AftercareEditTarget?

    var body: some View {
        List {
            ForEach(ServiceCategory.allCases) { category in
                let items = (templates.value ?? []).filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { template in
                            Button {
                                editing = .existing(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name).font(.headline).foregroundStyle(.primary)
                                    Text(stepsSummary(template))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(.rect)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            RemoteStateOverlay(remote: templates, retry: load) {
                ContentUnavailableView {
                    Label("Шаблонов нет", systemImage: "cross.case")
                } description: {
                    Text("Шаблон — это серия сообщений по уходу, которую бот отправит клиенту после процедуры.")
                } actions: {
                    Button("Создать шаблон") { editing = .new }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(templates)
        .navigationTitle("Шаблоны ухода")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Новый шаблон", systemImage: "plus") { editing = .new }
            }
        }
        .sheet(item: $editing) { target in
            AftercareTemplateEditorView(template: target.template) { change in
                switch change {
                case .saved(let template): templates.upsert(template)
                case .deleted(let id): templates.remove(id: id)
                }
                reference.replaceTemplates(templates.value ?? [])
            }
        }
    }

    private func stepsSummary(_ template: AftercareTemplate) -> String {
        let days = template.steps.map(\.dayOffset).sorted()
        let count = Plural.count(template.steps.count, one: "сообщение", few: "сообщения", many: "сообщений")
        guard let last = days.last, last > 0 else { return count }
        return "\(count) · до \(Plural.days(last))"
    }

    private func load() async {
        await templates.load { try await api.aftercareTemplates() }
        if let value = templates.value { reference.replaceTemplates(value) }
    }
}

enum AftercareEditTarget: Identifiable {
    case new
    case existing(AftercareTemplate)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let template): "template-\(template.id)"
        }
    }

    var template: AftercareTemplate? {
        if case .existing(let template) = self { return template }
        return nil
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AftercareTemplatesView()
    }
    .previewEnvironment()
}
#endif
