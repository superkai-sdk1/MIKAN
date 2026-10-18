import SwiftUI

/// A chat in the list: name, staff badge, last message, unread count.
struct ChatRow: View {
    let chat: BotChat

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InitialsAvatar(name: chat.displayName, color: avatarColor, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(chat.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if chat.isStaff {
                        StatusBadge(text: "Сотрудник", color: avatarColor, systemImage: "person.badge.shield.checkmark")
                            .fixedSize()
                    }
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

    private var avatarColor: Color {
        if let employee = chat.employee { return .master(employee.color) }
        return chat.client == nil ? .blue : .accentColor
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
        List {
            ChatRow(chat: PreviewData.chat)
            ChatRow(chat: PreviewData.staffChat)
        }
    }
    .previewEnvironment()
}
#endif
