import SwiftUI

/// Chat-like sandbox for `POST /bot/test`. The transcript is local only — nothing goes to Telegram.
struct BotTestView: View {
    private struct Entry: Identifiable {
        enum Author { case staff, bot, error }

        let id = UUID()
        let author: Author
        let text: String
        let date = Date.now
    }

    @Environment(APIClient.self) private var api
    @State private var transcript: [Entry] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var position = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                Label("Вы пишете как анонимный клиент. Бот отвечает по текущей базе знаний, в Telegram ничего не уходит.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                    .padding(.bottom, 8)
                ForEach(transcript) { entry in
                    bubble(entry)
                }
                if isSending {
                    HStack {
                        ProgressView()
                        Text("Бот печатает…").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom) {
            ChatComposer(text: $draft, placeholder: "Вопрос от имени клиента", isSending: isSending, onSend: send)
        }
        .navigationTitle("Проверить бота")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Очистить", systemImage: "trash") { transcript = [] }
                    .disabled(transcript.isEmpty || isSending)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ entry: Entry) -> some View {
        let isStaff = entry.author == .staff
        HStack {
            if !isStaff { Spacer(minLength: 48) }
            VStack(alignment: isStaff ? .leading : .trailing, spacing: 3) {
                if !isStaff {
                    Label(entry.author == .error ? "Ошибка" : "ИИ", systemImage: entry.author == .error ? "exclamationmark.triangle" : "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(entry.author == .bot ? ChatMarkdown.render(entry.text) : AttributedString(entry.text))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(background(entry.author), in: .rect(cornerRadius: 18))
            }
            if isStaff { Spacer(minLength: 48) }
        }
    }

    private func background(_ author: Entry.Author) -> Color {
        switch author {
        case .staff: Color(.secondarySystemBackground)
        case .bot: Color.accentColor.opacity(0.16)
        case .error: Color.red.opacity(0.14)
        }
    }

    private func send() {
        let text = draft.trimmed
        guard !text.isEmpty else { return }
        draft = ""
        transcript.append(Entry(author: .staff, text: text))
        isSending = true
        Task {
            defer {
                isSending = false
                withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
            }
            do {
                let reply = try await api.testBot(text: text)
                transcript.append(Entry(author: .bot, text: reply.reply))
            } catch {
                transcript.append(Entry(author: .error, text: error.userMessage))
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BotTestView()
    }
    .previewEnvironment()
}
#endif
