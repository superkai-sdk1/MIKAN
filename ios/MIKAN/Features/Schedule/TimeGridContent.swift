import SwiftUI

/// Scrollable body of the time grid: hour gutter, Canvas-drawn lines, appointment blocks, now line.
struct TimeGridContent: View {
    static let gutterWidth: CGFloat = 46

    let days: [Date]
    let appointments: [Appointment]
    let hourHeight: CGFloat
    let compact: Bool
    let onCreate: (Date) -> Void

    private var calendar: Calendar { .app }
    private var todayIndex: Int? { days.firstIndex { calendar.isDateInToday($0) } }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HourGutter(hourHeight: hourHeight)
                .frame(width: Self.gutterWidth)
            GeometryReader { proxy in
                let columnWidth = proxy.size.width / CGFloat(max(1, days.count))
                ZStack(alignment: .topLeading) {
                    GridLines(dayCount: days.count, hourHeight: hourHeight, todayIndex: todayIndex, showsHalfHours: !compact)
                        .contentShape(.rect)
                        .onTapGesture { location in
                            createAppointment(at: location, columnWidth: columnWidth)
                        }
                        .accessibilityHidden(true)
                    ForEach(blocks(columnWidth: columnWidth)) { block in
                        NavigationLink(value: block.appointment) {
                            AppointmentBlock(appointment: block.appointment, compact: compact, height: block.frame.height)
                        }
                        .buttonStyle(.plain)
                        .frame(width: block.frame.width, height: block.frame.height)
                        .offset(x: block.frame.minX, y: block.frame.minY)
                    }
                    if let todayIndex {
                        NowLine(hourHeight: hourHeight)
                            .frame(width: columnWidth)
                            .offset(x: CGFloat(todayIndex) * columnWidth)
                    }
                }
            }
        }
        .frame(height: hourHeight * 24)
    }

    private struct Block: Identifiable {
        let id: String
        let appointment: Appointment
        let frame: CGRect
    }

    private func blocks(columnWidth: CGFloat) -> [Block] {
        let byId = Dictionary(appointments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let intervals = appointments.map { TimeGridLayout.Interval(id: $0.id, start: $0.startsAt, end: $0.endsAt) }
        let inset: CGFloat = 1.5
        return days.enumerated().flatMap { dayIndex, day in
            let segments = TimeGridLayout.segments(of: intervals, dayStart: day, calendar: calendar)
            return TimeGridLayout.placements(for: segments).compactMap { placement -> Block? in
                guard let appointment = byId[placement.id] else { return nil }
                let laneWidth = columnWidth / CGFloat(placement.laneCount)
                let top = TimeGridLayout.y(forMinute: Double(placement.startMinute), hourHeight: hourHeight)
                let bottom = TimeGridLayout.y(forMinute: Double(placement.endMinute), hourHeight: hourHeight)
                let minHeight = TimeGridLayout.y(forMinute: Double(TimeGridLayout.minimumLayoutMinutes), hourHeight: hourHeight)
                let frame = CGRect(
                    x: CGFloat(dayIndex) * columnWidth + CGFloat(placement.lane) * laneWidth + inset,
                    y: top + inset,
                    width: max(laneWidth - inset * 2, 4),
                    height: max(bottom - top, minHeight) - inset * 2
                )
                return Block(id: "\(placement.id)-\(dayIndex)", appointment: appointment, frame: frame)
            }
        }
    }

    private func createAppointment(at location: CGPoint, columnWidth: CGFloat) {
        guard !days.isEmpty, columnWidth > 0 else { return }
        let dayIndex = min(max(0, Int(location.x / columnWidth)), days.count - 1)
        let minute = TimeGridLayout.slotStart(forY: location.y, hourHeight: hourHeight)
        guard let start = calendar.date(byAdding: .minute, value: minute, to: days[dayIndex]) else { return }
        onCreate(start)
    }
}

/// Hour labels drawn in a single Canvas.
private struct HourGutter: View {
    let hourHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            for hour in 1..<24 {
                let label = Text(String(format: "%02d:00", hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                context.draw(label, at: CGPoint(x: size.width - 6, y: CGFloat(hour) * hourHeight), anchor: .trailing)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Hour/half-hour lines, day separators, off-hours shading and today's tint — one Canvas, no per-cell views.
private struct GridLines: View {
    let dayCount: Int
    let hourHeight: CGFloat
    let todayIndex: Int?
    let showsHalfHours: Bool

    var body: some View {
        Canvas { context, size in
            let columnWidth = size.width / CGFloat(max(1, dayCount))
            let offHours = CGRect(x: 0, y: 0, width: size.width, height: CGFloat(TimeGridLayout.workdayStartHour) * hourHeight)
            context.fill(Path(offHours), with: .color(.secondary.opacity(0.06)))
            if let todayIndex {
                let column = CGRect(x: CGFloat(todayIndex) * columnWidth, y: 0, width: columnWidth, height: size.height)
                context.fill(Path(column), with: .color(.accentColor.opacity(0.05)))
            }
            var hours = Path()
            var halves = Path()
            for hour in 0...24 {
                let y = CGFloat(hour) * hourHeight
                hours.move(to: CGPoint(x: 0, y: y))
                hours.addLine(to: CGPoint(x: size.width, y: y))
                if showsHalfHours, hour < 24 {
                    halves.move(to: CGPoint(x: 0, y: y + hourHeight / 2))
                    halves.addLine(to: CGPoint(x: size.width, y: y + hourHeight / 2))
                }
            }
            var separators = Path()
            for index in 0...dayCount {
                let x = CGFloat(index) * columnWidth
                separators.move(to: CGPoint(x: x, y: 0))
                separators.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(hours, with: .color(Color(.separator)), lineWidth: 0.5)
            context.stroke(halves, with: .color(Color(.separator).opacity(0.45)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            context.stroke(separators, with: .color(Color(.separator)), lineWidth: 0.5)
        }
    }
}

/// Red current-time line, refreshed every minute.
private struct NowLine: View {
    let hourHeight: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let minute = TimeGridLayout.minuteOfDay(timeline.date, calendar: .app)
            let y = TimeGridLayout.y(forMinute: Double(minute), hourHeight: hourHeight)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.red)
                    .frame(height: 1.5)
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .offset(x: -4)
            }
            .offset(y: y - 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
