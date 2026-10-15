import SwiftUI

struct ChatsListView: View {
    @Environment(APIClient.self) private var api
    @Environment(AppState.self) private var appState
    @State private var chats = Remote<[BotChat]>()
    @State private var search = ""

    private static let pollInterval: Duration = .seconds(15)

    private var filtered: [BotChat] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return chats.value ?? [] }
        return (chats.value ?? []).filter { chat in
            [chat.displayName, chat.username, chat.telegramName, chat.client?.phone]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { chat in
                NavigationLink {
                    ChatView(chat: chat) { updated in chats.upsert(updated) }
                } label: {
                    ChatRow(chat: chat)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Имя или @username")
        .overlay {
            RemoteStateOverlay(remote: chats, isEmpty: { _ in filtered.isEmpty }, retry: load) {
                if search.trimmed.isEmpty {
                    ContentUnavailableView(
                        "Чатов пока нет",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Когда клиенты напишут боту в Telegram, переписка появится здесь.")
                    )
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        .remoteErrorAlert(chats)
        .navigationTitle("Чаты")
    }

    private func load() async {
        await chats.load { try await api.chats() }
        await appState.refreshBadges()
    }
}

private struct ChatRow: View {
    let chat: BotChat

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InitialsAvatar(name: chat.displayName, color: chat.client == nil ? .blue : .accentColor, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if chat.aiPaused {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("ИИ на паузе")
                    }
                    Spacer(minLength: 8)
                    Text(DateText.relative(chat.lastMessage?.createdAt ?? chat.updatedAt))
                        .font(.caption)
                        .foregroundStyle(chat.unreadCount > 0 ? Color.accentColor : Color.secondary)
                }
                HStack(alignment: .top) {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if chat.needsAttention {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Нужен ответ сотрудника")
                    }
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: .capsule)
                            .accessibilityLabel("Непрочитанных: \(chat.unreadCount)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var preview: String {
        guard let message = chat.lastMessage else { return "Нет сообщений" }
        let prefix = switch message.role {
        case .user: ""
        case .assistant: "ИИ: "
        case .staff: "\(message.employee?.name ?? "Сотрудник"): "
        case .system: "Авто: "
        }
        return prefix + message.text
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        List { ChatRow(chat: PreviewData.chat) }
    }
    .previewEnvironment()
}
#endif
