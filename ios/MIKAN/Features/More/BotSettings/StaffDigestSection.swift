import SwiftUI

/// Bot settings: the morning and evening summaries the bot sends to staff chats — on/off and the time (studio time).
struct StaffDigestSection: View {
    @Binding var settings: BotSettings

    var body: some View {
        Section {
            ForEach(StaffDigest.allCases, id: \.self) { digest in
                Toggle(digest.title, isOn: isOn(digest).animation())
                if let time = settings[keyPath: digest.keyPath] {
                    DatePicker("Время", selection: date(digest, time: time), displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, DigestTime.timeZone)
                        .accessibilityLabel("\(digest.title): время")
                }
            }
        } header: {
            Text("Сводки для сотрудников")
        } footer: {
            Text("Бот присылает сотрудникам в Telegram: утром — что на сегодня и на что обратить внимание, вечером — итоги дня и завтрашние записи. Приходит в чаты сотрудников, которых бот узнал.")
        }
    }

    private func isOn(_ digest: StaffDigest) -> Binding<Bool> {
        Binding {
            settings[keyPath: digest.keyPath] != nil
        } set: { isOn in
            settings[keyPath: digest.keyPath] = digest.toggled(settings[keyPath: digest.keyPath], isOn: isOn)
        }
    }

    /// A malformed server value shows the default time until it is changed.
    private func date(_ digest: StaffDigest, time: String) -> Binding<Date> {
        Binding {
            DigestTime.date(from: time) ?? DigestTime.date(from: digest.defaultTime) ?? .now
        } set: { date in
            settings[keyPath: digest.keyPath] = DigestTime.text(from: date)
        }
    }
}
