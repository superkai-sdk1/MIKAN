import SwiftUI

/// "@" + text field for a username (Telegram nick, Instagram).
struct ClientHandleField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Text("@").foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(title)
        }
    }
}

/// «Указать дату рождения» and the date itself once switched on.
struct ClientBirthdayFields: View {
    @Binding var draft: ClientDraft

    var body: some View {
        Toggle("Указать дату рождения", isOn: $draft.hasBirthday.animation())
        if draft.hasBirthday {
            DatePicker("Дата рождения", selection: $draft.birthday, in: ...Date.now, displayedComponents: .date)
        }
    }
}
