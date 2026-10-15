import SwiftUI

/// Finds the bot chat for a client or a Telegram chat id and shows it.
struct ChatResolverView: View {
    enum Lookup {
        /// `GET /clients/:id/chat`.
        case client(id: Int)
        /// Scans `GET /bot/chats` (booking requests know only the Telegram chat id).
        case telegramChat(id: Int64)
    }

    @Environment(APIClient.self) private var api
    let title: String
    let lookup: Lookup
    @State private var resolved = Remote<BotChat?>()

    var body: some View {
        Group {
            if let value = resolved.value {
                if let chat = value {
                    ChatView(chat: chat)
                } else {
                    ContentUnavailableView(
                        "Чат не найден",
                        systemImage: "bubble.left.and.exclamationmark.bubble.right",
                        description: Text("Клиент ещё не писал боту в Telegram.")
                    )
                    .navigationTitle(title)
                }
            } else {
                RemoteStateOverlay(remote: resolved, retry: load)
                    .navigationTitle(title)
            }
        }
        .task { await load() }
    }

    private func load() async {
        await resolved.load {
            switch lookup {
            case .client(let id): try await api.clientChat(clientId: id)
            case .telegramChat(let id): try await api.chats().first { $0.chatId == id }
            }
        }
    }
}

struct ClientChatView: View {
    let client: ClientRef

    var body: some View {
        ChatResolverView(title: client.name, lookup: .client(id: client.id))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ClientChatView(client: PreviewData.ivanRef)
    }
    .previewEnvironment()
}
#endif
