import SwiftUI

/// «Месяц»: paged Monday-first month grids with master-colored dots, and the selected day's list below.
struct MonthCalendarView: View {
    @Environment(ScheduleStore.self) private var store

    let base: CalendarPeriod
    @Binding var pageOffset: Int?
    let pagerID: UUID
    let query: (CalendarPeriod) -> ScheduleQuery
    let showsCancelled: Bool
    @Binding var selectedDay: Date
    let onOpenDay: (Date) -> Void

    private var currentPeriod: CalendarPeriod { base.shifted(by: pageOffset ?? 0) }

    private var dayAppointments: [Appointment] {
        let all = store.appointments(for: query(currentPeriod)) ?? []
        return all
            .filter { Calendar.app.isDate($0.startsAt, inSameDayAs: selectedDay) && (showsCancelled || $0.isActive) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                monthControls
                PeriodPager(offset: $pageOffset) { index in
                    let period = base.shifted(by: index)
                    MonthGridPage(
                        period: period,
                        appointments: visible(store.appointments(for: query(period)) ?? []),
                        selectedDay: $selectedDay,
                        onOpenDay: onOpenDay
                    )
                }
                .id(pagerID)
                .frame(height: MonthGridPage.height)
                if let error = store.error(for: query(currentPeriod)) {
                    LoadErrorBanner(message: error) { await store.reload(query(currentPeriod)) }
                }
                selectedDaySection
            }
            .padding(.bottom, 96)
        }
        .refreshable { await store.reload(query(currentPeriod)) }
    }

    private func visible(_ items: [Appointment]) -> [Appointment] {
        showsCancelled ? items : items.filter(\.isActive)
    }

    /// Month summary; paging ‹ › lives in the shared period bar above.
    private var monthControls: some View {
        HStack {
            if store.isLoading(query(currentPeriod)) {
                ProgressView().controlSize(.small)
            } else {
                let count = visible(store.appointments(for: query(currentPeriod)) ?? []).filter { currentPeriod.contains($0.startsAt) }.count
                Text("\(Plural.appointments(count)) за месяц")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(DateText.dayTitle(selectedDay))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Открыть день") { onOpenDay(selectedDay) }
                    .font(.subheadline.weight(.semibold))
            }
            if dayAppointments.isEmpty {
                Text("Записей нет — нажмите «+», чтобы записать клиента.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(dayAppointments) { appointment in
                NavigationLink(value: appointment) {
                    AppointmentCard(appointment: appointment).cardStyle(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Month grid: six Monday-first weeks, up to three master-colored dots per day plus "+N".
struct MonthGridPage: View {
    static let cellHeight: CGFloat = 50
    static let height: CGFloat = 24 + cellHeight * 6 + 5 * 4

    let period: CalendarPeriod
    let appointments: [Appointment]
    @Binding var selectedDay: Date
    let onOpenDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private static let weekdaySymbols: [String] = {
        let symbols = Calendar.app.shortStandaloneWeekdaySymbols
        let mondayFirst = Array(symbols[1...]) + [symbols[0]]
        return mondayFirst.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }()

    var body: some View {
        let byDay = Dictionary(grouping: appointments) { Calendar.app.startOfDay(for: $0.startsAt) }
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 20)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(period.days(), id: \.self) { day in
                    MonthDayCell(
                        day: day,
                        inMonth: period.contains(day),
                        isSelected: Calendar.app.isDate(day, inSameDayAs: selectedDay),
                        appointments: byDay[day] ?? []
                    )
                    .onTapGesture { withAnimation(.snappy) { selectedDay = day } }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenDay(day) })
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

private struct MonthDayCell: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let appointments: [Appointment]

    private static let maxDots = 3
    private var isToday: Bool { Calendar.app.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 4) {
            Text(DateText.dayNumber(day))
                .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: 30, height: 30)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().stroke(Color.accentColor, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 2) {
                ForEach(appointments.prefix(Self.maxDots)) { appointment in
                    Circle()
                        .fill(Color.master(appointment.master.color))
                        .frame(width: 5, height: 5)
                        .opacity(appointment.isActive ? 1 : 0.4)
                }
                if appointments.count > Self.maxDots {
                    Text("+\(appointments.count - Self.maxDots)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: MonthGridPage.cellHeight)
        .opacity(inMonth ? 1 : 0.35)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DateText.weekdayDayMonth(day)), \(Plural.appointments(appointments.count))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Двойное касание открывает день")
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }
}
