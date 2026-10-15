import SwiftUI

/// Bot knowledge base entries.
struct KnowledgeListView: View {
    @Environment(APIClient.self) private var api
    @State private var entries = Remote<[KnowledgeEntry]>()
    @State private var editing: KnowledgeEditTarget?
    @State private var pendingDelete: KnowledgeEntry?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(entries.value ?? []) { entry in
                    Button {
                        editing = .existing(entry)
                    } label: {
                        KnowledgeRow(entry: entry)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Удалить", systemImage: "trash") { pendingDelete = entry }
                            .tint(.red)
                    }
                }
            } footer: {
                if !(entries.value ?? []).isEmpty {
                    Text("Бот использует активные статьи, когда отвечает клиентам: цены, подготовка, противопоказания, адрес.")
                }
            }
        }
        .overlay {
            RemoteStateOverlay(remote: entries, retry: load) {
                ContentUnavailableView {
                    Label("База знаний пуста", systemImage: "books.vertical")
                } description: {
                    Text("Добавьте статьи — например, «Противопоказания» или «Как подготовиться к сеансу». Бот опирается на них в ответах.")
                } actions: {
                    Button("Добавить статью") { editing = .new }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(entries)
        .errorAlert($errorMessage)
        .navigationTitle("База знаний")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Новая статья", systemImage: "plus") { editing = .new }
            }
        }
        .sheet(item: $editing) { target in
            KnowledgeEditorView(entry: target.entry) { saved in
                entries.upsert(saved)
            }
        }
        .confirmationDialog(
            "Удалить статью?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Удалить «\(entry.title)»", role: .destructive) { delete(entry) }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Бот перестанет использовать эту информацию.")
        }
    }

    private func load() async {
        await entries.load { try await api.knowledge() }
    }

    private func delete(_ entry: KnowledgeEntry) {
        Task {
            do {
                try await api.deleteKnowledge(id: entry.id)
                withAnimation { entries.remove(id: entry.id) }
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

enum KnowledgeEditTarget: Identifiable {
    case new
    case existing(KnowledgeEntry)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let entry): "entry-\(entry.id)"
        }
    }

    var entry: KnowledgeEntry? {
        if case .existing(let entry) = self { return entry }
        return nil
    }
}

private struct KnowledgeRow: View {
    let entry: KnowledgeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !entry.active {
                    StatusBadge(text: "Выключена", color: .gray)
                }
            }
            Text(entry.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .opacity(entry.active ? 1 : 0.6)
    }
}

struct KnowledgeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    let entry: KnowledgeEntry?
    let onSaved: (KnowledgeEntry) -> Void

    @State private var title: String
    @State private var content: String
    @State private var active: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entry: KnowledgeEntry?, onSaved: @escaping (KnowledgeEntry) -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        _title = State(initialValue: entry?.title ?? "")
        _content = State(initialValue: entry?.content ?? "")
        _active = State(initialValue: entry?.active ?? true)
    }

    private var canSave: Bool { !title.trimmed.isEmpty && !content.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Заголовок") {
                    TextField("Например, «Противопоказания»", text: $title)
                }
                Section("Текст") {
                    TextField("Что бот должен знать", text: $content, axis: .vertical)
                        .lineLimit(8...30)
                }
                Section {
                    Toggle("Использовать в ответах", isOn: $active)
                }
            }
            .navigationTitle(entry == nil ? "Новая статья" : "Статья")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Сохранить", action: save).disabled(!canSave) }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        let body = KnowledgeBody(title: title.trimmed, content: content.trimmed, active: active, sort: entry?.sort)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = if let entry {
                    try await api.updateKnowledge(id: entry.id, body)
                } else {
                    try await api.createKnowledge(body)
                }
                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        KnowledgeListView()
    }
    .previewEnvironment()
}
#endif
