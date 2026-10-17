import SwiftUI

struct ClientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api

    let client: Client?
    let onSaved: (Client) -> Void

    @State private var draft: ClientDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(client: Client?, onSaved: @escaping (Client) -> Void) {
        self.client = client
        self.onSaved = onSaved
        _draft = State(initialValue: client.map(ClientDraft.init(client:)) ?? ClientDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя", text: $draft.name)
                        .textContentType(.givenName)
                    TextField("Фамилия", text: $draft.lastName)
                        .textContentType(.familyName)
                    Toggle("Указать дату рождения", isOn: $draft.hasBirthday.animation())
                    if draft.hasBirthday {
                        DatePicker("Дата рождения", selection: $draft.birthday, in: ...Date.now, displayedComponents: .date)
                    }
                } header: {
                    Text("Клиент")
                }
                Section {
                    TextField(draft.requiresPhone ? "Телефон" : "Телефон (не указан)", text: $draft.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    handleField("Ник в Telegram", text: $draft.telegramNick)
                    handleField("Instagram", text: $draft.instagram)
                } header: {
                    Text("Контакты")
                } footer: {
                    contactsFooter
                }
                Section {
                    Picker("Откуда узнал", selection: $draft.source) {
                        Text("Не указано").tag("")
                        ForEach(ClientSource.suggestions, id: \.self) { option in
                            Text(ClientSource.title(for: option)).tag(option)
                        }
                        if !draft.source.isEmpty, !ClientSource.suggestions.contains(draft.source) {
                            Text(ClientSource.title(for: draft.source)).tag(draft.source)
                        }
                    }
                }
                Section("Заметки") {
                    TextField("Аллергии, предпочтения, особенности", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("Сообщения от бота", isOn: $draft.botEnabled)
                } footer: {
                    Text("Разрешить боту присылать клиенту памятки по уходу и напоминания о записи.")
                }
            }
            .navigationTitle(client == nil ? "Новый клиент" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Сохранить", action: save).disabled(!draft.canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
        }
    }

    @ViewBuilder
    private var contactsFooter: some View {
        if let hint = draft.missingFieldsHint {
            Text("Обязательны имя и телефон. \(hint)")
        } else if !draft.requiresPhone, draft.phone.trimmed.isEmpty {
            Text("У клиента нет телефона (карточка из импорта). Добавьте его, когда узнаете.")
        }
    }

    /// "@" + text field for a username.
    private func handleField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text("@").foregroundStyle(.secondary)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(title)
        }
    }

    private func save() {
        let body = draft.body()
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = if let client {
                    try await api.updateClient(id: client.id, body)
                } else {
                    try await api.createClient(body)
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
    ClientEditorView(client: PreviewData.ivan) { _ in }
        .previewEnvironment()
}
#endif
