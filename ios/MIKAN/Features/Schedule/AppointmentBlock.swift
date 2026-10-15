import SwiftUI

/// Appointment in the time grid, tinted with the master's color.
struct AppointmentBlock: View {
    let appointment: Appointment
    let compact: Bool
    let height: CGFloat

    private var color: Color { .master(appointment.master.color) }
    private var showsTitle: Bool { !compact && height >= 44 }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
            Group {
                if compact {
                    // Week lanes can be very narrow: degrade instead of wrapping text into «1…».
                    ViewThatFits(in: .horizontal) {
                        details
                        VStack(alignment: .leading, spacing: 1) {
                            timeLabel
                            initialsLabel
                        }
                        initialsLabel
                        Color.clear.frame(width: 0, height: 0)
                    }
                } else {
                    details
                }
            }
            .padding(.horizontal, compact ? 3 : 5)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.2))
        .clipShape(.rect(cornerRadius: 6))
        .strikethrough(!appointment.isActive)
        .opacity(appointment.isActive ? 1 : 0.45)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .contentShape(.rect(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                timeLabel
                if appointment.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            Text(compact ? shortName : appointment.client.name)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(compact ? 2 : 1)
            if showsTitle {
                Text(appointment.displayTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var timeLabel: some View {
        Text(DateText.time(appointment.startsAt))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
    }

    private var initialsLabel: some View {
        Text(Initials.from(appointment.client.name))
            .font(.caption2.weight(.semibold))
    }

    /// First name, or initials when the name is long.
    private var shortName: String {
        let first = appointment.client.name.split(separator: " ").first.map(String.init) ?? appointment.client.name
        return first.count > 8 ? Initials.from(appointment.client.name) : first
    }

    private var accessibilityText: String {
        var parts = [
            DateText.timeRange(appointment.startsAt, appointment.endsAt),
            appointment.client.name,
            appointment.displayTitle,
            "мастер \(appointment.master.name)",
        ]
        if appointment.status != .scheduled { parts.append(appointment.status.title) }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview {
    HStack(alignment: .top, spacing: 4) {
        AppointmentBlock(appointment: PreviewData.appointments[0], compact: false, height: 120)
            .frame(height: 120)
        AppointmentBlock(appointment: PreviewData.appointments[2], compact: true, height: 40)
            .frame(width: 48, height: 40)
    }
    .padding()
}
#endif
