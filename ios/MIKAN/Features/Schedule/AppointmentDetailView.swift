import SwiftUI

struct AppointmentDetailView: View {
    @Environment(APIClient.self) private var api
    @Environment(AppState.self) private var appState
    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.openURL) private var openURL

    @State private var appointment: Appointment
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var editorDraft: AppointmentDraft?
    @State private var showsComplete = false
    @State private var pendingCheckout: Appointment?
    @State private var confirmsCancel = false
    @State private var confirmsNoShow = false
    @State private var showsChat = false
    @State private var successCount = 0

    init(appointment: Appointment) {
        _appointment = State(initialValue: appointment)
    }

    var body: some View {
        List {
            AppointmentHeaderSection(appointment: appointment)
            clientSection
            detailsSection
            if let notes = appointment.notes.nonEmpty {
                Section("Заметки") { Text(notes) }
            }
            paymentSection
            if !actions.isEmpty {
                actionsSection
            }
        }
        .navigationTitle("Запись")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appointment.isOpen {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Перенести") { editorDraft = .edit(appointment) }
                }
            }
        }
        .disabled(isWorking)
        .refreshable { await reload() }
        .task { await reload() }
        .navigationDestination(isPresented: $showsChat) {
            ClientChatView(client: appointment.client)
        }
        .sheet(item: $editorDraft) { draft in
            AppointmentEditorView(draft: draft) { saved in apply(saved) }
        }
        .sheet(isPresented: $showsComplete, onDismiss: startPendingCheckout) {
            CompleteAppointmentSheet(appointment: appointment) { completed in
                apply(completed)
            } onPay: { completed in
                pendingCheckout = completed
            }
        }
        .confirmationDialog("Отменить запись?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Отменить запись", role: .destructive) { setStatus(.cancelled) }
            Button("Не отменять", role: .cancel) {}
        } message: {
            Text("Клиенту не придёт напоминание об этой записи.")
        }
        .confirmationDialog("Отметить неявку?", isPresented: $confirmsNoShow, titleVisibility: .visible) {
            Button("Клиент не пришёл", role: .destructive) { setStatus(.noShow) }
            Button("Отмена", role: .cancel) {}
        }
        .errorAlert($errorMessage)
        .sensoryFeedback(.success, trigger: successCount)
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section("Клиент") {
            NavigationLink {
                ClientDetailView(clientId: appointment.client.id)
            } label: {
                HStack(spacing: 12) {
                    InitialsAvatar(name: appointment.client.name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appointment.client.name).font(.headline)
                        if let phone = appointment.client.phone.nonEmpty {
                            Text(PhoneText.display(phone)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if appointment.client.telegramLinked { TelegramBadge() }
                }
            }
            if let callURL = PhoneText.callURL(appointment.client.phone) {
                Button("Позвонить", systemImage: "phone.fill") { openURL(callURL) }
            }
            if appointment.client.telegramLinked {
                Button("Открыть чат в боте", systemImage: "bubble.left.and.bubble.right.fill") { showsChat = true }
            }
        }
    }

    private var detailsSection: some View {
        Section("Детали") {
            LabeledContent("Услуга", value: appointment.service?.name ?? "Без услуги")
            if let title = appointment.title.nonEmpty {
                LabeledContent("Описание", value: title)
            }
            LabeledContent("Мастер") {
                HStack(spacing: 6) {
                    Circle().fill(Color.master(appointment.master.color)).frame(width: 10, height: 10)
                    Text(appointment.master.name)
                }
            }
            LabeledContent("Стоимость") { MoneyText(appointment.price) }
            if appointment.deposit > 0 {
                LabeledContent("Предоплата") { MoneyText(appointment.deposit) }
            }
        }
    }

    @ViewBuilder
    private var paymentSection: some View {
        if let saleId = appointment.saleId {
            Section {
                NavigationLink {
                    SaleLoaderView(saleId: saleId)
                } label: {
                    Label("Оплачено", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                }
            }
        } else if appointment.status == .completed {
            Section {
                Button {
                    appState.startCheckout(for: appointment)
                } label: {
                    Label("Принять оплату · \(Money.format(appointment.price))", systemImage: "creditcard.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Откроется касса с услугой, клиентом и предоплатой.")
            }
        }
    }

    private enum Action: Hashable {
        case confirm, complete, reschedule, noShow, cancel, restore
    }

    private var actions: [Action] {
        switch appointment.status {
        case .scheduled: [.confirm, .complete, .reschedule, .noShow, .cancel]
        case .confirmed: [.complete, .reschedule, .noShow, .cancel]
        case .cancelled, .noShow: [.restore]
        case .completed: []
        }
    }

    private var actionsSection: some View {
        Section("Действия") {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .confirm:
                    Button("Подтвердить", systemImage: "checkmark.circle") { setStatus(.confirmed) }
                case .complete:
                    Button("Завершить", systemImage: "flag.checkered") { showsComplete = true }
                case .reschedule:
                    Button("Перенести", systemImage: "calendar.badge.clock") { editorDraft = .edit(appointment) }
                case .noShow:
                    Button("Неявка", systemImage: "person.fill.xmark") { confirmsNoShow = true }
                case .cancel:
                    Button("Отменить запись", systemImage: "xmark.circle", role: .destructive) { confirmsCancel = true }
                case .restore:
                    Button("Вернуть в запись", systemImage: "arrow.uturn.backward.circle") { setStatus(.scheduled) }
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        do {
            apply(try await api.appointment(id: appointment.id))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.userMessage
        }
    }

    private func apply(_ updated: Appointment) {
        appointment = updated
        schedule.upsert(updated)
    }

    private func setStatus(_ status: AppointmentStatus) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                apply(try await api.setAppointmentStatus(id: appointment.id, status))
                successCount += 1
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    private func startPendingCheckout() {
        guard let completed = pendingCheckout else { return }
        pendingCheckout = nil
        appState.startCheckout(for: completed)
    }
}

private struct AppointmentHeaderSection: View {
    let appointment: Appointment

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppointmentStatusBadge(status: appointment.status)
                    Spacer()
                    Text(DateText.duration(minutes: appointment.durationMin))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(DateText.timeRange(appointment.startsAt, appointment.endsAt))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(DateText.weekdayDayMonth(appointment.startsAt))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(appointment.displayTitle)
                    .font(.title3.weight(.semibold))
                    .padding(.top, 4)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AppointmentDetailView(appointment: PreviewData.appointments[0])
    }
    .previewEnvironment()
}
#endif
