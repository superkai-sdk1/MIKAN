import SwiftUI

/// The QR step of a checkout: shows the bank's SBP QR code to the client and polls the server until it reports
/// the payment. The server creates the sale itself, so a paid code hands back the finished `Sale`.
struct QRPaymentView: View {
    static let pollInterval = QRPaymentPolling.interval

    @Environment(APIClient.self) private var api

    let onPaid: (Sale) -> Void
    /// The bank has the money but the server could not sell the cart: staff finish the sale by hand.
    let onPaidWithoutSale: () -> Void
    /// Back to the checkout form (cancelled, expired, or leaving a code that could not be cancelled).
    let onBack: () -> Void
    /// A fresh code for the same cart after this one expired.
    let onRenew: () -> Void
    let isRenewing: Bool

    @State private var payment: QrPayment
    /// Expiry on the device clock: the code's lifetime counted from when it was shown, immune to clock skew.
    private let deadline: Date
    @State private var isCancelling = false
    /// Why the latest poll failed (connection or server); the server keeps checking the bank on its own.
    @State private var pollProblem: String?
    @State private var cancelFailure: String?

    init(
        payment: QrPayment,
        isRenewing: Bool,
        onPaid: @escaping (Sale) -> Void,
        onPaidWithoutSale: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onRenew: @escaping () -> Void
    ) {
        _payment = State(initialValue: payment)
        deadline = QRPaymentPolling.deadline(for: payment)
        self.isRenewing = isRenewing
        self.onPaid = onPaid
        self.onPaidWithoutSale = onPaidWithoutSale
        self.onBack = onBack
        self.onRenew = onRenew
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("К оплате").font(.subheadline).foregroundStyle(.secondary)
                    MoneyText(payment.amount)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                }
                .accessibilityElement(children: .combine)
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .safeAreaBar(edge: .bottom) {
            actions
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .task(id: payment.id) { await poll() }
        .alert("QR-код не отменён", isPresented: cancelFailureShown) {
            Button("Повторить", action: cancel)
            Button("Выйти без отмены", role: .destructive, action: onBack)
        } message: {
            Text("\(cancelFailure ?? "") Если клиент всё же оплатит этот код, продажа проведётся автоматически.")
        }
        .sensoryFeedback(.warning, trigger: payment.status == .expired)
    }

    private var cancelFailureShown: Binding<Bool> {
        Binding(get: { cancelFailure != nil }, set: { if !$0 { cancelFailure = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch payment.status {
        case .pending, .cancelled:
            QRCodePanel(payment: payment, deadline: deadline, pollProblem: pollProblem)
        case .paid:
            ContentUnavailableView {
                Label("Оплата получена", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } description: {
                Text("\(payment.error ?? "Продажа проводится…")\n\nСумма QR будет перенесена в «Перевод»: проверьте чек и проведите продажу. Если чек уже оплачен иначе, верните деньги клиенту в интернет-банке Точки.")
            }
        case .expired:
            ContentUnavailableView {
                Label("Время оплаты истекло", systemImage: "clock.badge.xmark")
            } description: {
                Text(payment.error ?? "Клиент не оплатил QR-код. Создайте новый или выберите другой способ оплаты.")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch payment.status {
        case .pending, .cancelled:
            Button(role: .cancel, action: cancel) {
                ZStack {
                    Text("Отменить оплату по QR").opacity(isCancelling ? 0 : 1)
                    if isCancelling { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(isCancelling)
        case .paid:
            primaryButton("Провести продажу вручную", action: onPaidWithoutSale)
        case .expired:
            VStack(spacing: 8) {
                // After a failed bank check the money may still have arrived: no second code then.
                if payment.error == nil {
                    Button(action: onRenew) {
                        ZStack {
                            Label("Новый QR-код", systemImage: "qrcode").opacity(isRenewing ? 0 : 1)
                            if isRenewing { ProgressView().tint(.white) }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(isRenewing)
                }
                Button("Выбрать другой способ оплаты", action: onBack)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private func poll() async {
        while payment.status == .pending, !Task.isCancelled {
            try? await Task.sleep(for: Self.pollInterval)
            guard !Task.isCancelled else { return }
            do {
                apply(try await api.qrPayment(id: payment.id))
                pollProblem = nil
            } catch {
                pollProblem = QRPaymentPolling.problemText(for: error)
            }
        }
    }

    private func apply(_ updated: QrPayment) {
        withAnimation(.smooth) { payment = updated }
        switch updated.status {
        case .paid:
            if let sale = updated.sale { onPaid(sale) }
        case .cancelled:
            onBack()
        case .pending, .expired:
            break
        }
    }

    private func cancel() {
        isCancelling = true
        Task {
            defer { isCancelling = false }
            do {
                apply(try await api.cancelQrPayment(id: payment.id))
            } catch {
                cancelFailure = error.userMessage
            }
        }
    }
}

/// Shared pieces of the SBP QR screens (checkout and prepayment): poll cadence, device-clock expiry, poll errors.
enum QRPaymentPolling {
    static let interval: Duration = .seconds(2)
    static let offlineText = "Нет связи с сервером — продолжаем проверять"

    /// Expiry on the device clock: the code's lifetime counted from when it was shown, immune to clock skew.
    static func deadline(for payment: QrPayment, shownAt: Date = .now) -> Date {
        shownAt.addingTimeInterval(max(0, payment.expiresAt.timeIntervalSince(payment.createdAt)))
    }

    /// Why the latest poll failed; the server keeps checking the bank on its own.
    static func problemText(for error: any Error) -> String {
        guard let error = error as? APIError else { return offlineText }
        if case .transport = error { return offlineText }
        return error.userMessage
    }
}

/// A pending SBP code: the QR image, what the client does, the live countdown and status lines.
struct QRCodePanel: View {
    let payment: QrPayment
    /// Device-clock expiry (`QRPaymentPolling.deadline`).
    let deadline: Date
    /// Why the latest poll failed, if it did.
    let pollProblem: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let isOverdue = now >= deadline
        return VStack(spacing: 16) {
            QRCodeImage(payload: payment.payload)
                .padding(20)
                .background(.white, in: .rect(cornerRadius: 28))
                .frame(maxWidth: 320)
                .opacity(isOverdue ? 0.25 : 1)
                .animation(.smooth, value: isOverdue)
            Text("Клиент сканирует код камерой телефона или в приложении банка и подтверждает оплату через СБП.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ProgressView()
                if isOverdue {
                    Text("Срок кода истёк — ждём последнее подтверждение банка")
                } else {
                    Text("Ждём оплату · \(Text(timerInterval: now...deadline, countsDown: true))")
                }
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            if let error = payment.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let pollProblem {
                Label(pollProblem, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        QRPaymentView(
            payment: PreviewData.qrPayment, isRenewing: false,
            onPaid: { _ in }, onPaidWithoutSale: {}, onBack: {}, onRenew: {}
        )
        .navigationTitle("Оплата по QR")
        .navigationBarTitleDisplayMode(.inline)
    }
    .previewEnvironment()
}
#endif
