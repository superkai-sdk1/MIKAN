import SwiftUI

struct IdentifiedStaffCode: Identifiable {
    let code: StaffCode
    var id: String { code.code }
}

/// The `/staff <code>` command that binds the work chat.
struct StaffCodeSheet: View {
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
struct BotLinkView: View {
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
