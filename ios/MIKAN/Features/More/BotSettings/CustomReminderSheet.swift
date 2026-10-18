import SwiftUI

/// A reminder moment that is not among the presets: days, hours and minutes before the appointment.
struct CustomReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let schedule: ReminderSchedule
    let onAdd: (ReminderSchedule) -> Void

    @State private var parts = ReminderParts(days: 0, hours: 4, minutes: 0)

    private static let dayValues = Array(0...(ReminderSchedule.maxMinutes / ReminderParts.minutesPerDay))
    private static let hourValues = Array(0..<24)
    private static let minuteValues = Array(stride(from: 0, to: 60, by: 5))

    private var issue: ReminderSchedule.Issue? { schedule.addIssue(for: parts.totalMinutes) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(ReminderSchedule.title(parts.totalMinutes) + " до записи")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: parts)
                HStack(spacing: 0) {
                    wheel("Дни", selection: $parts.days, values: Self.dayValues) { "\($0) дн." }
                    wheel("Часы", selection: $parts.hours, values: Self.hourValues) { "\($0) ч" }
                    wheel("Минуты", selection: $parts.minutes, values: Self.minuteValues) { "\($0) мин" }
                }
                Text(issue?.message ?? ReminderSchedule.limitsHint)
                    .font(.footnote)
                    .foregroundStyle(issue == nil ? Color.secondary : Color.red)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .navigationTitle("Своё время")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить", action: add).disabled(issue != nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func wheel(
        _ title: String,
        selection: Binding<Int>,
        values: [Int],
        text: @escaping (Int) -> String
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(text(value)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }

    private func add() {
        guard case .success(let updated) = schedule.adding(parts.totalMinutes) else { return }
        onAdd(updated)
        dismiss()
    }
}

#if DEBUG
#Preview {
    Text("Настройки")
        .sheet(isPresented: .constant(true)) {
            CustomReminderSheet(schedule: ReminderSchedule(offsets: [1440, 120])) { _ in }
        }
}
#endif
