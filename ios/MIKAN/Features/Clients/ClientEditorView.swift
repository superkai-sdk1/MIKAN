import SwiftUI

struct ClientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api

    let client: Client?
    let onSaved: (Client) -> Void

    @State private var name: String
    @State private var phone: String
    @State private var instagram: String
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var source: String
    @State private var notes: String
    @State private var botEnabled: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let defaultBirthday = Calendar.app.date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? .now

    init(client: Client?, onSaved: @escaping (Client) -> Void) {
        self.client = client
        self.onSaved = onSaved
        let birthdayDate = client?.birthday.flatMap { CalendarDay.date(from: $0) }
        _name = State(initialValue: client?.name ?? "")
        _phone = State(initialValue: client?.phone ?? "")
        _instagram = State(initialValue: client?.instagram ?? "")
        _hasBirthday = State(initialValue: birthdayDate != nil)
        _birthday = State(initialValue: birthdayDate ?? Self.defaultBirthday)
        _source = State(initialValue: client?.source ?? "")
        _notes = State(initialValue: client?.notes ?? "")
        _botEnabled = State(initialValue: client?.botEnabled ?? true)
    }

    private var canSave: Bool { !name.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Контакты") {
                    TextField("Имя и фамилия", text: $name)
                        .textContentType(.name)
                    TextField("Телефон", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    HStack(spacing: 4) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("Instagram", text: $instagram)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Toggle("Указать день рождения", isOn: $hasBirthday.animation())
                    if hasBirthday {
                        DatePicker("День рождения", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    }
                    Picker("Откуда узнал", selection: $source) {
                        Text("Не указано").tag("")
                        ForEach(ClientSource.suggestions, id: \.self) { option in
                            Text(ClientSource.title(for: option)).tag(option)
                        }
                        if !source.isEmpty, !ClientSource.suggestions.contains(source) {
                            Text(ClientSource.title(for: source)).tag(source)
                        }
                    }
                }
                Section("Заметки") {
                    TextField("Аллергии, предпочтения, особенности", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("Сообщения от бота", isOn: $botEnabled)
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
                        Button("Сохранить", action: save).disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        let cleanedInstagram = instagram.trimmed.hasPrefix("@") ? String(instagram.trimmed.dropFirst()) : instagram
        let body = ClientBody(
            name: name.trimmed,
            phone: Nullable(phone.nonEmpty),
            instagram: Nullable(cleanedInstagram.nonEmpty),
            birthday: Nullable(hasBirthday ? CalendarDay.string(from: birthday) : nil),
            notes: Nullable(notes.nonEmpty),
            source: Nullable(source.nonEmpty),
            botEnabled: botEnabled
        )
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
