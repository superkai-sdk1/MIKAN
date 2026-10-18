import SwiftUI

/// Completes an appointment: aftercare message, consumables used, then offers to take payment.
struct CompleteAppointmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference

    let appointment: Appointment
    let onCompleted: (Appointment) -> Void
    let onPay: (Appointment) -> Void

    @State private var sendsAftercare: Bool
    @State private var templateId: Int?
    @State private var consumables = Remote<[Product]>()
    @State private var usage: [Int: Int] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var result: CompleteAppointmentResult?

    init(
        appointment: Appointment,
        onCompleted: @escaping (Appointment) -> Void,
        onPay: @escaping (Appointment) -> Void
    ) {
        self.appointment = appointment
        self.onCompleted = onCompleted
        self.onPay = onPay
        _sendsAftercare = State(initialValue: appointment.client.telegramLinked)
    }

    private var isTelegramLinked: Bool { appointment.client.telegramLinked }
    /// Some service of the visit is a fresh piercing / tattoo: only then the server sends a memo.
    private var hasFreshProcedure: Bool { AftercareDefaults.sendsMemo(for: appointment, services: reference.services) }
    private var canSendAftercare: Bool { isTelegramLinked && hasFreshProcedure }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    CompletionSuccessView(appointment: result.appointment, scheduledMessages: result.scheduledMessages) {
                        onPay(result.appointment)
                        dismiss()
                    } onDone: {
                        dismiss()
                    }
                } else {
                    form
                }
            }
            .navigationTitle(result == nil ? "Завершить запись" : "Готово")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Button("Завершить") { submit() }
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .errorAlert($errorMessage)
            .sensoryFeedback(.success, trigger: result != nil)
            .task { await load() }
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Отправить памятку по уходу", isOn: $sendsAftercare)
                    .disabled(!canSendAftercare)
                if sendsAftercare && canSendAftercare {
                    Picker("Шаблон", selection: $templateId) {
                        Text("Не выбран").tag(Int?.none)
                        ForEach(reference.templates) { template in
                            Text(template.name).tag(Int?.some(template.id))
                        }
                    }
                }
            } header: {
                Text("Уход")
            } footer: {
                if !isTelegramLinked {
                    Text("У клиента не подключён Telegram — памятку отправить нельзя. Подключите бота в карточке клиента.")
                } else if !hasFreshProcedure {
                    Text(AftercareDefaults.noFreshProcedureHint)
                } else if sendsAftercare && templateId == nil {
                    Text("Выберите шаблон, иначе памятка не будет отправлена.").foregroundStyle(.orange)
                } else {
                    Text("Первое сообщение придёт через несколько минут, остальные — по расписанию шаблона.")
                }
            }
            consumablesSection
        }
    }

    @ViewBuilder
    private var consumablesSection: some View {
        Section {
            if let products = consumables.value {
                if products.isEmpty {
                    Text("Расходников на складе нет").foregroundStyle(.secondary)
                }
                ForEach(products) { product in
                    Stepper(value: usageBinding(for: product.id), in: 0...max(0, product.quantity)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name)
                                Text("На складе: \(product.quantity) \(product.unitLabel)")
                                    .font(.caption)
                                    .foregroundStyle(product.lowStock ? Color.red : Color.secondary)
                            }
                            Spacer()
                            Text("\(usage[product.id] ?? 0)")
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(product.quantity <= 0)
                }
            } else if let failure = consumables.failure {
                Text(failure).foregroundStyle(.red)
                Button("Повторить") { Task { await loadConsumables() } }
            } else {
                ProgressView()
            }
        } header: {
            Text("Расходники")
        } footer: {
            Text("Будут списаны со склада как расход на процедуру.")
        }
    }

    private func usageBinding(for productId: Int) -> Binding<Int> {
        Binding(
            get: { usage[productId] ?? 0 },
            set: { usage[productId] = $0 }
        )
    }

    private func load() async {
        async let consumablesLoad: Void = loadConsumables()
        do {
            try await reference.ensureTemplates()
            try await reference.ensureServices()
            if templateId == nil {
                templateId = defaultTemplateId()
            }
            if !hasFreshProcedure {
                sendsAftercare = false
            }
        } catch {
            errorMessage = error.userMessage
        }
        await consumablesLoad
    }

    private func loadConsumables() async {
        await consumables.load { try await api.products(kind: .consumable) }
    }

    private func defaultTemplateId() -> Int? {
        AftercareDefaults.templateId(for: appointment, services: reference.services, templates: reference.templates)
    }

    private func submit() {
        let used = usage
            .filter { $0.value > 0 }
            .map { ConsumableUse(productId: $0.key, quantity: $0.value) }
            .sorted { $0.productId < $1.productId }
        let body = CompleteBody(
            sendAftercare: sendsAftercare && canSendAftercare,
            aftercareTemplateId: sendsAftercare ? templateId : nil,
            consumables: used
        )
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let completed = try await api.completeAppointment(id: appointment.id, body)
                onCompleted(completed.appointment)
                withAnimation(.smooth) { result = completed }
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

/// Aftercare memo of an appointment, mirroring the server: memos go out only for services marked «Свежий прокол» /
/// «Свежее тату» (`Service.freshProcedure`).
nonisolated enum AftercareDefaults {
    static let noFreshProcedureHint =
        "В записи нет услуги со «Свежим проколом» или «Свежим тату» — памятка по уходу не отправляется. " +
        "Переключатель — в карточке услуги."

    /// A catalog service of the visit: its template and category, when it may send a memo.
    private struct Candidate {
        let templateId: Int?
        let category: ServiceCategory?
    }

    /// The visit's catalog services in line order (the legacy single service when it has no lines) that may send a memo:
    /// fresh ones, plus ones missing from `services` (not loaded yet — the server decides for those).
    private static func candidates(for appointment: Appointment, services: [Service]) -> [Candidate] {
        let refs: [(id: Int, category: ServiceCategory?)] = appointment.services.isEmpty
            ? [appointment.service].compactMap { $0.map { ($0.id, $0.category) } }
            : appointment.services.compactMap { line in line.serviceId.map { ($0, line.category) } }
        return refs.compactMap { ref in
            guard let service = services.first(where: { $0.id == ref.id }) else {
                return Candidate(templateId: nil, category: ref.category)
            }
            return service.freshProcedure ? Candidate(templateId: service.aftercareTemplateId, category: service.category) : nil
        }
    }

    /// Completing the appointment can send a memo: one of its services is a fresh procedure.
    static func sendsMemo(for appointment: Appointment, services: [Service]) -> Bool {
        !candidates(for: appointment, services: services).isEmpty
    }

    /// The template of the first fresh service that has one; else the first template of that service's category.
    static func templateId(
        for appointment: Appointment,
        services: [Service],
        templates: [AftercareTemplate]
    ) -> Int? {
        let fresh = candidates(for: appointment, services: services)
        for candidate in fresh {
            if let templateId = candidate.templateId, templates.contains(where: { $0.id == templateId }) {
                return templateId
            }
        }
        guard let category = fresh.lazy.compactMap(\.category).first else { return nil }
        return templates.first { $0.category == category }?.id
    }
}

private struct CompletionSuccessView: View {
    let appointment: Appointment
    let scheduledMessages: Int
    let onPay: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)
                .accessibilityHidden(true)
            Text("Запись завершена")
                .font(.title2.weight(.bold))
            if scheduledMessages > 0 {
                Text("Запланировано сообщений по уходу: \(scheduledMessages)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                if appointment.saleId == nil {
                    Button(action: onPay) {
                        Label("Принять оплату · \(Money.format(appointment.price))", systemImage: "creditcard.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                } else {
                    Label("Оплачено", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                Button(action: onDone) {
                    Text("Готово").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(24)
    }
}

#if DEBUG
#Preview {
    CompleteAppointmentSheet(appointment: PreviewData.appointments[0]) { _ in } onPay: { _ in }
        .previewEnvironment()
}
#endif
