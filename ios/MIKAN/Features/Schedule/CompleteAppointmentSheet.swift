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

    private var canSendAftercare: Bool { appointment.client.telegramLinked }

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
                if sendsAftercare {
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
                if !canSendAftercare {
                    Text("У клиента не подключён Telegram — памятку отправить нельзя. Подключите бота в карточке клиента.")
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
        } catch {
            errorMessage = error.userMessage
        }
        await consumablesLoad
    }

    private func loadConsumables() async {
        await consumables.load { try await api.products(kind: .consumable) }
    }

    /// The service's template, or the first template of the same category.
    private func defaultTemplateId() -> Int? {
        if let id = reference.service(id: appointment.service?.id)?.aftercareTemplateId,
           reference.template(id: id) != nil {
            return id
        }
        guard let category = appointment.service?.category else { return nil }
        return reference.templates.first { $0.category == category }?.id
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
