import SwiftUI

/// QR code + share link that binds the client's Telegram chat to this client card.
struct TelegramLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    let clientId: Int
    let clientName: String

    @State private var link = Remote<LinkResponse>()
    @State private var copiedCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let url = link.value.flatMap({ URL(string: $0.url) }) {
                        content(url: url)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if link.value == nil {
                    RemoteStateOverlay(remote: link, retry: load)
                }
            }
            .navigationTitle("Подключить бота")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть", role: .close) { dismiss() }
                }
            }
            .task { await load() }
            .sensoryFeedback(.success, trigger: copiedCount)
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func content(url: URL) -> some View {
        Text("Попросите \(clientName) навести камеру телефона на QR-код или отправьте ссылку. Бот откроется в Telegram и привяжет чат к карточке клиента.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        QRCodeView(text: url.absoluteString, size: 230)
            .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
        Text(url.absoluteString)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .multilineTextAlignment(.center)
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ShareLink(item: url, message: Text("Подключите бота MIKAN STUDIO: напоминания о записи и памятки по уходу")) {
                    Label("Отправить ссылку", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button {
                    UIPasteboard.general.url = url
                    copiedCount += 1
                } label: {
                    Label("Копировать", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }

    private func load() async {
        await link.load { try await api.telegramLink(clientId: clientId) }
    }
}

#if DEBUG
#Preview {
    TelegramLinkSheet(clientId: 1, clientName: "Иван")
        .previewEnvironment()
}
#endif
