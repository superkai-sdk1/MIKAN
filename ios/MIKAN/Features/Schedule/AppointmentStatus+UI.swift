import SwiftUI

extension AppointmentStatus {
    var title: String {
        switch self {
        case .scheduled: "Запланирована"
        case .confirmed: "Подтверждена"
        case .completed: "Завершена"
        case .cancelled: "Отменена"
        case .noShow: "Неявка"
        }
    }

    var color: Color {
        switch self {
        case .scheduled: .blue
        case .confirmed: .teal
        case .completed: .green
        case .cancelled: .gray
        case .noShow: .red
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: "clock"
        case .confirmed: "checkmark.circle"
        case .completed: "flag.checkered"
        case .cancelled: "xmark.circle"
        case .noShow: "person.fill.xmark"
        }
    }
}

struct AppointmentStatusBadge: View {
    let status: AppointmentStatus

    var body: some View {
        StatusBadge(text: status.title, color: status.color)
    }
}
