import SwiftUI

/// Where the prepayment screen is.
enum DepositCollectStep: Equatable {
    /// Amount, «Клиент оплатил» and the SBP options.
    case choose
    /// An SBP code shown on the phone.
    case qr(QrPayment)
    case done(DepositReceipt)
}

/// What was just received, for the success state.
struct DepositReceipt: Equatable {
    let amount: Int
    let method: PaymentMethod
    /// Server note on a paid QR code (above the required amount, appointment already paid…).
    var issue: String?
}

/// Takes an appointment's prepayment: recorded as paid at the studio, shown as an SBP QR code, or sent as a
/// payment link (bot or share sheet). Works pushed after creating an appointment and inside its own sheet.
struct DepositCollectView: View {
    static let receiveMethods: [PaymentMethod] = [.cash, .card, .transfer]
    /// A sent link is checked less often than a code on the screen.
    private static let linkPollInterval: Duration = .seconds(5)

    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference

    let bookingChatId: Int64?
    let onChange: (Appointment) -> Void
    let onClose: () -> Void

    @State private var appointment: Appointment
    @State private var amount: Int
    @State private var method: PaymentMethod = .cash
    @State private var step = DepositCollectStep.choose
    /// The latest link sent or shared from here (initially the appointment's pending one).
    @State private var link: QrPayment?
    /// Why the link was not sent (bot error, no chat, QR not configured…).
    @State private var linkProblem: String?
    @State private var linkPollProblem: String?
    @State private var reloadProblem: String?
    @State private var running: DepositRequest?
    @State private var errorMessage: String?
    @State private var retryMessage: String?
    @State private var receiveKey = IdempotencyKey()
    @State private var successCount = 0

    init(
        appointment: Appointment,
        bookingChatId: Int64? = nil,
        onChange: @escaping (Appointment) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        _appointment = State(initialValue: appointment)
        _amount = State(initialValue: DepositSummary.missing(appointment))
        _link = State(initialValue: appointment.depositLink?.status == .pending ? appointment.depositLink : nil)
        self.bookingChatId = bookingChatId
        self.onChange = onChange
        self.onClose = onClose
    }

    private var isChoosing: Bool { step == .choose }
    private var isDone: Bool {
        if case .done = step { return true }
        return false
    }

    var body: some View {
        content
            .navigationTitle("Предоплата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isChoosing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(DepositSummary.missing(appointment) > 0 ? "Позже" : "Закрыть", action: onClose)
                            .disabled(running != nil)
                    }
                }
                if isDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово", action: onClose)
                    }
                }
            }
            .interactiveDismissDisabled((!isChoosing && !isDone) || running != nil)
            .task { try? await reference.ensureQrPaymentsConfig() }
            .errorAlert($errorMessage)
            .retryAlert($retryMessage, title: "Предоплата могла записаться", retry: receive)
            .sensoryFeedback(.success, trigger: successCount)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .choose:
            chooseForm
                .task(id: link?.id) { await pollLink() }
        case .qr(let payment):
            DepositQRStep(
                payment: payment,
                isRenewing: running == .screen,
                onPaid: { paid in Task { await finishPaid(paid) } },
                onRenew: showQr,
                onBack: { withAnimation(.smooth) { step = .choose } }
            )
            .id(payment.id)
        case .done(let receipt):
            DepositDoneView(
                receipt: receipt,
                appointment: appointment,
                reloadProblem: reloadProblem,
                onMore: moreAction,
                onDone: onClose
            )
        }
    }

    private var chooseForm: some View {
        Form {
            DepositCollectHeader(appointment: appointment)
            Section {
                NumberField.money("Сумма", value: $amount)
            } footer: {
                amountFooter
            }
            DepositReceiveSection(method: $method, amount: amount, isRunning: running == .receive, onReceive: receive)
            if reference.qrPaymentsEnabled {
                DepositSBPSection(
                    link: link,
                    linkProblem: linkProblem,
                    pollProblem: linkPollProblem,
                    canStart: amount > 0,
                    running: running,
                    shareText: shareText(for:),
                    onScreen: showQr,
                    onTelegram: sendToTelegram,
                    onLink: createLink
                )
            }
        }
        .disabled(running != nil)
    }

    @ViewBuilder
    private var amountFooter: some View {
        let missing = DepositSummary.missing(appointment)
        if amount <= 0 {
            Text("Укажите сумму предоплаты.")
        } else if missing > 0, amount > missing {
            Text("Больше, чем осталось внести (\(Money.format(missing))).").foregroundStyle(.orange)
        }
    }

    // MARK: - Actions

    private func receive() {
        let body = DepositReceiveBody(amount: amount, method: method)
        let key = receiveKey.key(for: body)
        running = .receive
        Task {
            defer { running = nil }
            do {
                update(try await api.receiveDeposit(appointmentId: appointment.id, body, idempotencyKey: key))
                receiveKey.reset()
                finish(DepositReceipt(amount: body.amount, method: body.method))
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если предоплата уже записана, второй раз она не запишется."
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    /// A code on the phone screen; it cancels the appointment's other pending codes (a sent link too).
    private func showQr() {
        request(.screen, DepositQrBody(delivery: .screen, amount: amount)) { result in
            link = nil
            withAnimation(.smooth) { step = .qr(result.payment) }
        } onError: { message in
            errorMessage = message
        }
    }

    private func sendToTelegram() {
        request(.telegram, DepositQrBody(delivery: .telegram, amount: amount, chatId: bookingChatId)) { result in
            link = result.payment
            if let sendError = result.sendError.nonEmpty {
                linkProblem = "Не удалось отправить: \(sendError)"
            } else {
                successCount += 1
            }
        } onError: { message in
            linkProblem = message
        }
    }

    private func createLink() {
        request(.link, DepositQrBody(delivery: .link, amount: amount)) { result in
            link = result.payment
        } onError: { message in
            linkProblem = message
        }
    }

    private func request(
        _ kind: DepositRequest,
        _ body: DepositQrBody,
        onSuccess: @escaping @MainActor (DepositLinkResult) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        running = kind
        linkProblem = nil
        Task {
            defer { running = nil }
            do {
                let result = try await api.createDepositQr(appointmentId: appointment.id, body)
                update(result.appointment)
                onSuccess(result)
            } catch {
                onError(error.userMessage)
            }
        }
    }

    /// While a link is waiting on this screen, a payment shows up here without leaving it.
    private func pollLink() async {
        while let current = link, current.status == .pending, !Task.isCancelled {
            try? await Task.sleep(for: Self.linkPollInterval)
            guard !Task.isCancelled, link?.id == current.id else { return }
            do {
                let updated = try await api.qrPayment(id: current.id)
                linkPollProblem = nil
                link = updated
                if updated.status == .paid { await finishPaid(updated) }
            } catch {
                linkPollProblem = QRPaymentPolling.problemText(for: error)
            }
        }
    }

    /// The bank confirmed a code: the server has recorded the prepayment, so the appointment is reloaded.
    private func finishPaid(_ payment: QrPayment) async {
        do {
            update(try await api.appointment(id: appointment.id))
            reloadProblem = nil
        } catch {
            reloadProblem = "Запись не обновилась: \(error.userMessage) Обновите её карточку позже."
        }
        link = nil
        finish(DepositReceipt(amount: payment.amount, method: .qr, issue: payment.error.nonEmpty))
    }

    private func finish(_ receipt: DepositReceipt) {
        amount = DepositSummary.missing(appointment)
        successCount += 1
        withAnimation(.smooth) { step = .done(receipt) }
    }

    /// «Принять ещё» on the success state, while the appointment can still take a prepayment.
    private var moreAction: (() -> Void)? {
        guard appointment.isOpen else { return nil }
        return collectMore
    }

    private func collectMore() {
        amount = DepositSummary.missing(appointment)
        withAnimation(.smooth) { step = .choose }
    }

    private func update(_ updated: Appointment) {
        appointment = updated
        onChange(updated)
    }

    private func shareText(for payment: QrPayment) -> String {
        DepositText.shareMessage(amount: payment.amount, startsAt: appointment.startsAt, payload: payment.payload)
    }
}

/// The request in flight (its button shows a spinner).
enum DepositRequest {
    case receive, screen, telegram, link
}

#if DEBUG
#Preview("Ждём предоплату") {
    NavigationStack {
        DepositCollectView(appointment: PreviewData.appointments[1]) {}
    }
    .previewEnvironment()
}
#endif
