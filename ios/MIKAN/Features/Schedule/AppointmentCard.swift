import SwiftUI

/// Appointment row: time range, client, service, master color stripe, status and price.
struct AppointmentCard: View {
    let appointment: Appointment
    var showsDate = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.master(appointment.master.color))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(timeText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    AppointmentStatusBadge(status: appointment.status)
                }
                Text(appointment.client.name)
                    .font(.headline)
                    .strikethrough(!appointment.isActive)
                Text("\(appointment.displayTitle) · \(appointment.master.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    MoneyText(appointment.price)
                        .font(.subheadline.weight(.medium))
                    if appointment.deposit > 0 {
                        Text("предоплата \(Money.format(appointment.deposit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if appointment.saleId != nil {
                        Label("Оплачено", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(appointment.isActive ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let range = DateText.timeRange(appointment.startsAt, appointment.endsAt)
        return showsDate ? "\(DateText.dayMonth(appointment.startsAt)), \(range)" : range
    }
}

#if DEBUG
#Preview {
    List(PreviewData.appointments) { appointment in
        AppointmentCard(appointment: appointment)
    }
    .listRowSpacing(10)
    .previewEnvironment()
}
#endif
