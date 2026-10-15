import SwiftUI

struct StudioSettingsView: View {
    @Environment(APIClient.self) private var api
    @State private var remote = Remote<StudioSettings>()
    @State private var settings: StudioSettings?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedCount = 0

    /// Common Russian time zones.
    static let timeZones: [(id: String, title: String)] = [
        ("Europe/Kaliningrad", "Калининград (UTC+2)"),
        ("Europe/Moscow", "Москва (UTC+3)"),
        ("Europe/Samara", "Самара (UTC+4)"),
        ("Asia/Yekaterinburg", "Екатеринбург (UTC+5)"),
        ("Asia/Omsk", "Омск (UTC+6)"),
        ("Asia/Novosibirsk", "Новосибирск (UTC+7)"),
        ("Asia/Tomsk", "Томск (UTC+7)"),
        ("Asia/Krasnoyarsk", "Красноярск (UTC+7)"),
        ("Asia/Irkutsk", "Иркутск (UTC+8)"),
        ("Asia/Yakutsk", "Якутск (UTC+9)"),
        ("Asia/Vladivostok", "Владивосток (UTC+10)"),
        ("Asia/Magadan", "Магадан (UTC+11)"),
        ("Asia/Kamchatka", "Камчатка (UTC+12)"),
    ]

    private var hasChanges: Bool { settings != nil && settings != remote.value }

    var body: some View {
        Form {
            if let settings = Binding($settings) {
                Section("Студия") {
                    TextField("Название", text: settings.name)
                    TextField("Адрес", text: settings.address, axis: .vertical)
                    TextField("Телефон", text: settings.phone)
                        .keyboardType(.phonePad)
                    TextField("Часы работы", text: settings.workingHours)
                }
                Section("Онлайн") {
                    TextField("Instagram", text: settings.instagram)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Сайт", text: settings.website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("Пара слов о студии, мастерах, стиле", text: settings.about, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("О студии")
                } footer: {
                    Text("Эти сведения бот использует в ответах клиентам.")
                }
                Section {
                    Picker("Часовой пояс", selection: settings.timezone) {
                        ForEach(timeZoneOptions(current: settings.wrappedValue.timezone), id: \.id) { zone in
                            Text(zone.title).tag(zone.id)
                        }
                    }
                } footer: {
                    Text("По нему считаются дни в отчётах и время отправки памяток.")
                }
            }
        }
        .overlay {
            if settings == nil { RemoteStateOverlay(remote: remote, retry: load) }
        }
        .navigationTitle("Настройки студии")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else { Button("Сохранить", action: save).disabled(!hasChanges) }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(remote)
        .errorAlert($errorMessage)
        .sensoryFeedback(.success, trigger: savedCount)
    }

    private func timeZoneOptions(current: String) -> [(id: String, title: String)] {
        guard !Self.timeZones.contains(where: { $0.id == current }), !current.isEmpty else { return Self.timeZones }
        return Self.timeZones + [(current, current)]
    }

    private func load() async {
        let keepsLocalEdits = hasChanges
        await remote.load { try await api.studioSettings() }
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
                let saved = try await api.saveStudioSettings(settings)
                remote.set(saved)
                self.settings = saved
                savedCount += 1
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StudioSettingsView()
    }
    .previewEnvironment()
}
#endif
