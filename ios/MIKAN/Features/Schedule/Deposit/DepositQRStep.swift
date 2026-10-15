import SwiftUI

/// A prepayment SBP code on the phone screen: polls the server until the bank confirms the payment
/// (the server records the prepayment itself), offers a new code once it expires.
struct DepositQRStep: View {
    @Environment(APIClient.self) private var api

    let isRenewing: Bool
    let onPaid: (QrPayment) -> Void
    /// A fresh code after this one expired.
    let onRenew: () -> Void
    /// Back to the prepayment options (cancelled or expired).
    let onBack: () -> Void

    @State private var payment: QrPayment
    private let deadline: Date
    @State private var pollProblem: String?
    @State private var isCancelling = false
    @State private var cancelFailure: String?

    init(
        payment: QrPayment,
        isRenewing: Bool,
        onPaid: @escaping (QrPayment) -> Void,
        onRenew: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        _payment = State(initialValue: payment)
        deadline = QRPaymentPolling.deadline(for: payment)
        self.isRenewing = isRenewing
        self.onPaid = onPaid
        self.onRenew = onRenew
        self.onBack = onBack
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
        .errorAlert($cancelFailure, title: "QR-код не отменён")
        .sensoryFeedback(.warning, trigger: payment.status == .expired)
    }

    @ViewBuilder
    private var content: some View {
        switch payment.status {
        case .pending, .cancelled:
            QRCodePanel(payment: payment, deadline: deadline, pollProblem: pollProblem)
        case .paid:
            ProgressView("Оплата получена, обновляем запись…")
                .padding(.top, 40)
        case .expired:
            ContentUnavailableView {
                Label("Время оплаты истекло", systemImage: "clock.badge.xmark")
            } description: {
                Text(payment.error ?? "Клиент не оплатил QR-код. Создайте новый или выберите другой способ.")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch payment.status {
        case .pending, .cancelled:
            Button(role: .cancel, action: cancel) {
                ZStack {
                    Text("Отменить QR-код").opacity(isCancelling ? 0 : 1)
                    if isCancelling { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(isCancelling)
        case .paid:
            EmptyView()
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
                Button("Другой способ оплаты", action: onBack)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        }
    }

    private func poll() async {
        while payment.status == .pending, !Task.isCancelled {
            try? await Task.sleep(for: QRPaymentPolling.interval)
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
        case .paid: onPaid(updated)
        case .cancelled: onBack()
        case .pending, .expired: break
        }
    }

    /// The server checks the bank first, so a payment that has just arrived comes back as paid.
    private func cancel() {
        isCancelling = true
        Task {
            defer { isCancelling = false }
            do {
                apply(try await api.cancelQrPayment(id: payment.id))
            } catch {
                cancelFailure = "\(error.userMessage) Если клиент всё же оплатит этот код, предоплата запишется автоматически."
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DepositQRStep(payment: PreviewData.qrPayment, isRenewing: false, onPaid: { _ in }, onRenew: {}, onBack: {})
            .navigationTitle("Предоплата")
            .navigationBarTitleDisplayMode(.inline)
    }
    .previewEnvironment()
}
#endif
