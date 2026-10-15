import SwiftUI

struct BotSettingsView: View {
    @Environment(APIClient.self) private var api
    @State private var remote = Remote<BotSettings>()
    @State private var settings: BotSettings?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedCount = 0
    @State private var staffCode: StaffCode?
    @State private var isRequestingCode = false

    private static let reminderOptions = [2, 3, 6, 12, 24, 48]

    private var hasChanges: Bool { settings != nil && settings != remote.value }

    var body: some View {
        Form {
            if let settings = Binding($settings) {
                statusSection(settings.wrappedValue)
                behaviourSection(settings)
                messagesSection(settings)
                staffChatSection(settings.wrappedValue)
            }
        }
        .overlay {
            if settings == nil { RemoteStateOverlay(remote: remote, retry: load) }
        }
        .navigationTitle("Настройки бота")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Сохранить", action: save).disabled(!hasChanges)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(remote)
        .errorAlert($errorMessage)
        .sensoryFeedback(.success, trigger: savedCount)
        .sheet(item: Binding(get: { staffCode.map(IdentifiedStaffCode.init) }, set: { staffCode = $0?.code })) { item in
            StaffCodeSheet(code: item.code)
        }
    }

    private func statusSection(_ settings: BotSettings) -> some View {
        Section("Состояние") {
            if let username = settings.botUsername.nonEmpty, let url = URL(string: "https://t.me/\(username)") {
                NavigationLink {
                    BotLinkView(username: username, url: url)
                } label: {
                    LabeledContent("Бот", value: "@\(username)")
                }
            } else {
                LabeledContent("Бот", value: "Не подключён")
            }
            statusRow("ИИ настроен", isOn: settings.aiConfigured)
            statusRow("Рабочий чат привязан", isOn: settings.staffChatBound)
        }
    }

    private func statusRow(_ title: String, isOn: Bool) -> some View {
        LabeledContent(title) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isOn ? Color.green : Color.red)
                .accessibilityLabel(isOn ? "Да" : "Нет")
        }
    }

    private func behaviourSection(_ settings: Binding<BotSettings>) -> some View {
        Section {
            Toggle("Бот включён", isOn: settings.enabled)
            Toggle("Отвечает ИИ", isOn: settings.aiEnabled)
            Toggle("Напоминания о записи", isOn: settings.remindersEnabled)
            if settings.wrappedValue.remindersEnabled {
                Picker("Напоминать за", selection: settings.reminderHoursBefore) {
                    ForEach(reminderOptions(including: settings.wrappedValue.reminderHoursBefore), id: \.self) { hours in
                        Text(Plural.count(hours, one: "час", few: "часа", many: "часов")).tag(hours)
                    }
                }
            }
            Picker("Памятки по уходу в", selection: settings.aftercareHour) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).tag(hour)
                }
            }
        } header: {
            Text("Поведение")
        } footer: {
            Text("Сообщения ухода со второго дня приходят в указанное время по часовому поясу студии.")
        }
    }

    private func reminderOptions(including current: Int) -> [Int] {
        Array(Set(Self.reminderOptions + [current])).sorted()
    }

    private func messagesSection(_ settings: Binding<BotSettings>) -> some View {
        Group {
            Section {
                TextField("Здравствуйте! Я помощник MIKAN STUDIO…", text: settings.greeting, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Приветствие")
            } footer: {
                Text("Первое сообщение, которое клиент получает после /start.")
            }
            Section {
                TextField("Например: всегда предлагай записаться на консультацию", text: settings.extraInstructions, axis: .vertical)
                    .lineLimit(3...10)
            } header: {
                Text("Дополнительные инструкции для ИИ")
            }
        }
    }

    private func staffChatSection(_ settings: BotSettings) -> some View {
        Section {
            Button {
                requestStaffCode()
            } label: {
                HStack {
                    Label(settings.staffChatBound ? "Привязать другой рабочий чат" : "Подключить рабочий чат", systemImage: "person.3.sequence")
                    if isRequestingCode {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRequestingCode)
        } footer: {
            Text("В рабочий чат Telegram бот присылает новые заявки и вопросы, на которые нужен ответ сотрудника.")
        }
    }

    private func load() async {
        let keepsLocalEdits = hasChanges
        await remote.load { try await api.botSettings() }
        if let value = remote.value, !keepsLocalEdits {
            settings = value
        }
    }

    private func save() {
        guard let settings else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = try await api.saveBotSettings(settings)
                remote.set(saved)
                self.settings = saved
                savedCount += 1
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    private func requestStaffCode() {
        isRequestingCode = true
        Task {
            defer { isRequestingCode = false }
            do {
                staffCode = try await api.staffCode()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

private struct IdentifiedStaffCode: Identifiable {
    let code: StaffCode
    var id: String { code.code }
}

private struct StaffCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let code: StaffCode
    @State private var copiedCount = 0

    private var command: String { "/staff \(code.code)" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(code.instruction)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text(command)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                    .accessibilityLabel("Команда: \(command)")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
                Button {
                    UIPasteboard.general.string = command
                    copiedCount += 1
                } label: {
                    Label("Скопировать команду", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Text("Код действует до \(DateText.time(code.expiresAt)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Рабочий чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", role: .close) { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: copiedCount)
        }
        .presentationDetents([.medium])
    }
}

/// QR code and share link for `https://t.me/<username>`.
private struct BotLinkView: View {
    let username: String
    let url: URL

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Клиенты могут отсканировать код камерой, чтобы открыть бота студии.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                QRCodeView(text: url.absoluteString, size: 240)
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
                Text("@\(username)").font(.title3.weight(.semibold))
                ShareLink(item: url) {
                    Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .navigationTitle("Ссылка на бота")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BotSettingsView()
    }
    .previewEnvironment()
}
#endif
