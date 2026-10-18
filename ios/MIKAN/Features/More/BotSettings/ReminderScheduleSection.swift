import SwiftUI

/// Reminders in the bot settings: on/off, the moments before the appointment (earliest first),
/// add from presets or a custom value, remove while more than one is left.
struct ReminderScheduleSection: View {
    @Binding var isEnabled: Bool
    @Binding var schedule: ReminderSchedule
    /// Older servers keep a single reminder in whole hours.
    let supportsSeveral: Bool

    @State private var isAddingCustom = false

    var body: some View {
        Section {
            Toggle("Напоминания о записи", isOn: $isEnabled.animation())
            if isEnabled {
                ForEach(schedule.offsets, id: \.self) { offset in
                    row(offset)
                        .deleteDisabled(!schedule.canRemove)
                }
                .onDelete(perform: delete)
                addMenu
            }
        } header: {
            Text("Напоминания")
        } footer: {
            footer
        }
        .sheet(isPresented: $isAddingCustom) {
            CustomReminderSheet(schedule: schedule) { updated in
                withAnimation { schedule = updated }
            }
        }
    }

    private func row(_ offset: Int) -> some View {
        HStack {
            Label(ReminderSchedule.title(offset), systemImage: "bell")
            Spacer()
            if schedule.canRemove {
                Button {
                    withAnimation { schedule = schedule.removing(offset) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Удалить напоминание \(ReminderSchedule.label(offset))")
            }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(schedule.availablePresets, id: \.self) { preset in
                Button(ReminderSchedule.title(preset)) { add(preset) }
            }
            Divider()
            Button("Своё время…", systemImage: "slider.horizontal.3") { isAddingCustom = true }
        } label: {
            Label(
                schedule.canAdd ? "Добавить напоминание" : "Не больше \(ReminderSchedule.maxCount) напоминаний",
                systemImage: "plus.circle.fill"
            )
        }
        .disabled(!schedule.canAdd)
    }

    @ViewBuilder
    private var footer: some View {
        if !isEnabled {
            Text("Бот не напоминает клиентам о записях.")
        } else if let issue = schedule.issue {
            Text(issue.message).foregroundStyle(.red)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let preview = schedule.preview {
                    Text(preview + ".")
                }
                Text("«Приду» подтверждает запись. «Перенести» — бот предложит свободное время и сам перенесёт запись; попросить перенос клиент может и обычным сообщением.")
                if !supportsSeveral {
                    Text("Сервер ещё не обновлён: сохранится только самое раннее напоминание, с точностью до часа.")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func add(_ minutes: Int) {
        guard case .success(let updated) = schedule.adding(minutes) else { return }
        withAnimation { schedule = updated }
    }

    private func delete(_ indexes: IndexSet) {
        let removed = indexes.map { schedule.offsets[$0] }
        withAnimation { schedule = removed.reduce(schedule) { $0.removing($1) } }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var isEnabled = true
    @Previewable @State var schedule = ReminderSchedule(offsets: [1440, 120])
    Form {
        ReminderScheduleSection(isEnabled: $isEnabled, schedule: $schedule, supportsSeveral: true)
    }
}
#endif
