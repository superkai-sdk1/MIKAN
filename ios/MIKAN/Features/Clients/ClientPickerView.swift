import SwiftUI

/// Searchable client picker with an inline "new client" form. Pops back after picking.
struct ClientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Binding var selection: ClientRef?
    var suggestion: ClientSuggestion?

    @State private var search = ""
    @State private var results = Remote<[Client]>()
    @State private var showsNewForm = false
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private static let searchDebounce: Duration = .milliseconds(300)

    var body: some View {
        List {
            Section {
                DisclosureGroup(isExpanded: $showsNewForm) {
                    TextField("Имя и фамилия", text: $newName)
                        .textContentType(.name)
                    TextField("Телефон", text: $newPhone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Button {
                        createClient()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Создать и выбрать")
                        }
                    }
                    .disabled(newName.trimmed.isEmpty || isCreating)
                } label: {
                    Label("Новый клиент", systemImage: "person.badge.plus")
                }
            }
            if let clients = results.value, !clients.isEmpty {
                Section(search.trimmed.isEmpty ? "Клиенты" : "Найдено") {
                    ForEach(clients) { client in
                        Button {
                            selection = client.ref
                            dismiss()
                        } label: {
                            ClientRow(client: client, isSelected: client.id == selection?.id)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Имя, телефон, Instagram")
        .overlay {
            RemoteStateOverlay(remote: results, retry: load) {
                if search.trimmed.isEmpty {
                    ContentUnavailableView(
                        "Клиентов пока нет",
                        systemImage: "person.2",
                        description: Text("Создайте клиента в блоке «Новый клиент» выше.")
                    )
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
            .padding(.top, 120)
        }
        .task(id: search) {
            if !search.isEmpty {
                try? await Task.sleep(for: Self.searchDebounce)
                guard !Task.isCancelled else { return }
            }
            await load()
        }
        .navigationTitle("Клиент")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($errorMessage)
        .onAppear(perform: applySuggestion)
    }

    private func load() async {
        let query = search
        await results.load { try await api.clients(search: query, limit: 50).items }
    }

    private func applySuggestion() {
        guard let suggestion, newName.isEmpty, newPhone.isEmpty else { return }
        newName = suggestion.name
        newPhone = suggestion.phone
        showsNewForm = true
    }

    private func createClient() {
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let client = try await api.createClient(ClientBody(
                    name: newName.trimmed,
                    phone: Nullable(newPhone.nonEmpty),
                    instagram: nil,
                    birthday: nil,
                    notes: nil,
                    source: nil,
                    botEnabled: true
                ))
                selection = client.ref
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

/// Client list row: avatar, name, phone, Telegram badge.
struct ClientRow: View {
    let client: Client
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: client.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if client.archived {
                StatusBadge(text: "Архив", color: .gray)
            }
            if client.telegramLinked {
                TelegramBadge()
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String? {
        if let phone = client.phone.nonEmpty { return PhoneText.display(phone) }
        if let instagram = client.instagram.nonEmpty { return "@\(instagram)" }
        return nil
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ClientPickerView(selection: .constant(nil))
    }
    .previewEnvironment()
}
#endif
