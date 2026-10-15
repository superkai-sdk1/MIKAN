import SwiftUI

extension View {
    /// Presents the prepayment flows of the appointment card: the prepayment screen, refund, retain,
    /// the reminder and the refund-or-retain question after a cancellation / no-show.
    func appointmentDepositFlows(
        _ flow: Binding<DepositFlow?>,
        appointment: Appointment,
        onChange: @escaping (Appointment) -> Void
    ) -> some View {
        modifier(AppointmentDepositFlows(flow: flow, appointment: appointment, onChange: onChange))
    }
}

private struct AppointmentDepositFlows: ViewModifier {
    @Environment(APIClient.self) private var api

    @Binding var flow: DepositFlow?
    let appointment: Appointment
    let onChange: (Appointment) -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var notice: DepositNotice?
    @State private var retainKey = IdempotencyKey()
    @State private var successCount = 0

    private var held: String { Money.format(appointment.deposit) }

    func body(content: Content) -> some View {
        content
            .disabled(isWorking)
            .sheet(isPresented: shows(.collect)) {
                NavigationStack {
                    DepositCollectView(appointment: appointment, onChange: onChange) { flow = nil }
                }
            }
            .sheet(isPresented: shows(.refund)) {
                DepositRefundSheet(appointment: appointment) { updated in
                    onChange(updated)
                    successCount += 1
                }
            }
            .confirmationDialog("Удержать предоплату \(held)?", isPresented: shows(.retain), titleVisibility: .visible) {
                Button("Удержать \(held)", role: .destructive, action: retain)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Деньги останутся у студии, клиенту они не вернутся.")
            }
            .confirmationDialog("Предоплата \(held)", isPresented: shows(.decide), titleVisibility: .visible) {
                Button("Вернуть клиенту") { flow = .refund }
                Button("Удержать", role: .destructive, action: retain)
                Button("Решить позже", role: .cancel) {}
            } message: {
                Text("Клиент внёс предоплату. Вернуть её или оставить студии? Решить можно и позже в карточке записи.")
            }
            .onChange(of: flow) { _, newFlow in
                if newFlow == .remind { remind() }
            }
            .alert(notice?.title ?? "", isPresented: noticeShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice?.message ?? "")
            }
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Удержание могло пройти", retry: retain)
            .sensoryFeedback(.success, trigger: successCount)
    }

    /// Presented while `flow` is `target`; dismissing clears it unless an action already moved on.
    private func shows(_ target: DepositFlow) -> Binding<Bool> {
        Binding(
            get: { flow == target },
            set: { isShown in
                if !isShown, flow == target { flow = nil }
            }
        )
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private func remind() {
        isWorking = true
        Task {
            defer {
                isWorking = false
                if flow == .remind { flow = nil }
            }
            do {
                let result = try await api.remindDeposit(appointmentId: appointment.id)
                onChange(result.appointment)
                let text = DepositText.remindNotice(result)
                notice = DepositNotice(title: text.title, message: text.message)
                if result.sendError.nonEmpty == nil { successCount += 1 }
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    private func retain() {
        let body = DepositRetainBody(reason: DepositText.retainReason(for: appointment.status))
        let key = retainKey.key(for: body)
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                onChange(try await api.retainDeposit(appointmentId: appointment.id, body, idempotencyKey: key))
                retainKey.reset()
                successCount += 1
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если предоплата уже удержана, второй раз это не запишется."
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

private struct DepositNotice {
    let title: String
    let message: String
}
