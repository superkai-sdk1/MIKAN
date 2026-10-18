import SwiftUI

/// How employees get the staff mode of the bot.
enum StaffBotHelp {
    static let howToLink = "Сотрудник пишет боту и нажимает «Поделиться номером» — если номер совпадает с номером в карточке сотрудника, бот узнаёт его."
}

/// Bot settings: how an employee links their own Telegram and what the bot gives them.
struct StaffBotSection: View {
    var body: some View {
        Section {
            Label(StaffBotHelp.howToLink, systemImage: "person.badge.shield.checkmark")
            Label("Узнанному сотруднику бот показывает записи, клиентов, аналитику и остатки склада.", systemImage: "chart.bar.doc.horizontal")
        } header: {
            Text("Сотрудники в боте")
        } footer: {
            Text("Чаты сотрудников отмечены в «Чатах». Там же привязку можно снять: «Отвязать сотрудника».")
        }
    }
}

#if DEBUG
#Preview {
    Form { StaffBotSection() }
}
#endif
