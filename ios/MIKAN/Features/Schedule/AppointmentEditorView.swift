import SwiftUI

/// Create / reschedule an appointment. Handles `409 schedule_conflict` with «Сохранить всё равно».
struct AppointmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(AppState.self) private var appState
    @Environment(ReferenceStore.self) private var reference

    @State private var draft: AppointmentDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var conflictMessage: String?
    @State private var referenceError: String?
    let onSaved: (Appointment) -> Void

    init(draft: AppointmentDraft, onSaved: @escaping (Appointment) -> Void) {
        _draft = State(initialValue: draft)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                clientSection
                masterSection
                AppointmentServicesSection(draft: $draft)
                timeSection
                paymentSection
                Section("Заметки") {
                    TextField("Пожелания, эскиз, зона…", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(draft.isEditing ? "Изменить запись" : "Новая запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Сохранить") { save(force: false) }
                            .disabled(!draft.isValid)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { await loadReference() }
            .errorAlert($errorMessage)
            .alert("Время занято", isPresented: conflictBinding) {
                Button("Сохранить всё равно") { save(force: true) }
                Button("Изменить время", role: .cancel) {}
            } message: {
                Text(conflictMessage ?? "")
            }
        }
    }

    private var clientSection: some View {
        Section("Клиент") {
            NavigationLink {
                ClientPickerView(selection: $draft.client, suggestion: draft.clientSuggestion)
            } label: {
                if let client = draft.client {
                    HStack(spacing: 12) {
                        InitialsAvatar(name: client.name, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(client.name).foregroundStyle(.primary)
                            if let phone = client.phone.nonEmpty {
                                Text(PhoneText.display(phone)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Label("Выберите клиента", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
    }

    private var masterSection: some View {
        Section {
            if reference.masters.isEmpty, referenceError == nil {
                LabeledContent("Мастер") { ProgressView() }
            } else {
                Picker("Мастер", selection: $draft.masterId) {
                    Text("Не выбран").tag(Int?.none)
                    ForEach(reference.masters) { master in
                        Text(master.name).tag(Int?.some(master.id))
                    }
                }
            }
        } footer: {
            if let referenceError {
                Text(referenceError).foregroundStyle(.red)
            }
        }
    }

    private var timeSection: some View {
        Section("Время") {
            DatePicker("Дата", selection: $draft.start, displayedComponents: .date)
            DatePicker("Начало", selection: $draft.start, displayedComponents: .hourAndMinute)
            Stepper(value: $draft.durationMin, in: AppointmentDraft.durationStep...(12 * 60), step: AppointmentDraft.durationStep) {
                LabeledContent("Длительность", value: DateText.duration(minutes: draft.durationMin))
            }
            DatePicker("Окончание", selection: endBinding, in: draft.start.addingTimeInterval(5 * 60)..., displayedComponents: .hourAndMinute)
        }
    }

    private var paymentSection: some View {
        Section {
            if draft.lines.isEmpty {
                NumberField.money("Стоимость", value: $draft.price)
            } else {
                LabeledContent("Стоимость") {
                    MoneyText(draft.total).foregroundStyle(.primary)
                }
                if draft.priceOverride != nil {
                    Button("Пересчитать по услугам", systemImage: "arrow.triangle.2.circlepath") {
                        draft.recalculateTotal()
                    }
                }
            }
            NumberField.money("Предоплата", value: $draft.deposit)
        } header: {
            Text("Оплата")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if draft.priceOverride != nil {
                    Text("Отличается от суммы услуг (\(Money.format(draft.linesTotal))). Изменение услуг или их цен пересчитает стоимость.")
                } else if !draft.lines.isEmpty {
                    Text("Сумма услуг — цену каждой можно изменить выше.")
                }
                if draft.deposit > draft.total {
                    Text("Предоплата больше стоимости.").foregroundStyle(.orange)
                }
            }
        }
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { draft.end },
            set: { newEnd in
                let minutes = Int(newEnd.timeIntervalSince(draft.start) / 60)
                draft.durationMin = max(5, minutes)
            }
        )
    }

    private var conflictBinding: Binding<Bool> {
        Binding(get: { conflictMessage != nil }, set: { if !$0 { conflictMessage = nil } })
    }

    private func loadReference() async {
        do {
            try await reference.ensureEmployees()
            try await reference.ensureServices()
            referenceError = nil
            if draft.masterId == nil, let me = appState.employee, me.isMaster, me.active {
                draft.masterId = me.id
            } else if draft.masterId == nil, reference.masters.count == 1 {
                draft.masterId = reference.masters.first?.id
            }
        } catch {
            referenceError = error.userMessage
        }
    }

    private func save(force: Bool) {
        guard let body = draft.body(force: force) else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved: Appointment
                if let id = draft.appointmentId {
                    saved = try await api.updateAppointment(id: id, body)
                } else {
                    saved = try await api.createAppointment(body)
                }
                onSaved(saved)
                dismiss()
            } catch let error as APIError where error.isScheduleConflict {
                conflictMessage = error.message
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    AppointmentEditorView(draft: .new(day: .now, client: PreviewData.ivanRef)) { _ in }
        .previewEnvironment()
}

#Preview("Несколько услуг") {
    AppointmentEditorView(draft: .edit(PreviewData.appointments[2])) { _ in }
        .previewEnvironment()
}
#endif
