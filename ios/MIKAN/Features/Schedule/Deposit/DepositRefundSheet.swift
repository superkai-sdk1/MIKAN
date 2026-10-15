import SwiftUI

/// «Вернуть клиенту»: how much of the held prepayment, how and why.
struct DepositRefundSheet: View {
    static let methods: [PaymentMethod] = [.cash, .card, .transfer, .qr]
    private static let reasonSuggestions = ["Отмена записи", "Перенос", "Ошибка при оплате"]

    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api

    let appointment: Appointment
    let onRefunded: (Appointment) -> Void

    @State private var amount: Int
    @State private var method: PaymentMethod
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var refundKey = IdempotencyKey()

    init(appointment: Appointment, onRefunded: @escaping (Appointment) -> Void) {
        self.appointment = appointment
        self.onRefunded = onRefunded
        _amount = State(initialValue: appointment.deposit)
        _method = State(initialValue: DepositSummary.latestReceiveMethod(appointment.depositOperations) ?? .cash)
    }

    private var amountMessage: String? { DepositRefundRules.amountMessage(amount, held: appointment.deposit) }
    private var canSave: Bool { amountMessage == nil && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField.money("Сумма", value: $amount)
                } footer: {
                    if let amountMessage {
                        Text(amountMessage).foregroundStyle(.red)
                    } else {
                        Text("Внесено за запись: \(Money.format(appointment.deposit))").monospacedDigit()
                    }
                }
                Section {
                    Picker("Способ", selection: $method) {
                        ForEach(Self.methods) { method in
                            Label(method.title, systemImage: method.symbol).tag(method)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Как вернуть")
                } footer: {
                    Text(DepositRefundRules.methodNote(method))
                }
                reasonSection
            }
            .disabled(isSaving)
            .navigationTitle("Возврат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Вернуть", action: save).disabled(!canSave) }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Возврат мог пройти", retry: save)
        }
    }

    private var reasonSection: some View {
        Section("Причина") {
            TextField("Необязательно", text: $reason, axis: .vertical)
                .lineLimit(1...3)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.reasonSuggestions, id: \.self) { suggestion in
                        Button(suggestion) { reason = suggestion }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func save() {
        let body = DepositRefundBody(amount: amount, method: method, reason: reason.trimmed.nonEmpty)
        let key = refundKey.key(for: body)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let updated = try await api.refundDeposit(appointmentId: appointment.id, body, idempotencyKey: key)
                refundKey.reset()
                onRefunded(updated)
                dismiss()
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если возврат уже записан, второй раз он не запишется."
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

/// Validation and hints of the refund sheet.
enum DepositRefundRules {
    static func amountMessage(_ amount: Int, held: Int) -> String? {
        if amount <= 0 { return "Укажите сумму возврата." }
        if amount > held { return "Не больше внесённой суммы (\(Money.format(held)))." }
        return nil
    }

    static func methodNote(_ method: PaymentMethod) -> String {
        switch method {
        case .cash: "Наличные выдаются из кассы — нужна открытая смена."
        case .qr: "Верните деньги в интернет-банке Точки — приложение только отметит возврат."
        case .card, .transfer: "Приложение только отметит возврат — сами деньги верните клиенту."
        }
    }
}

#if DEBUG
#Preview {
    DepositRefundSheet(appointment: PreviewData.appointments[0]) { _ in }
        .previewEnvironment()
}
#endif
