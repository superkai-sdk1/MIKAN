import SwiftUI

/// Checkout sheet: lines, client, appointment, discount, payment → «Провести продажу» → receipt.
/// With a QR share the button shows the bank's QR code first; the server sells the cart once it is paid.
struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    @Environment(ShiftStore.self) private var shift
    @Environment(ScheduleStore.self) private var schedule
    @Environment(ReferenceStore.self) private var reference

    @State private var completedSale: Sale?
    @State private var qrPayment: QrPayment?
    /// Result of completing the appointment in this checkout (kept across a failed sale and its retry).
    @State private var completion: CompleteAppointmentResult?
    @State private var receiptCashChange: Int?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var errorTitle = CheckoutView.saleFailedTitle
    @State private var confirmsClear = false
    @State private var retryMessage: String?

    private static let saleFailedTitle = "Продажа не проведена"

    var body: some View {
        NavigationStack {
            Group {
                if let completedSale {
                    SaleReceiptView(sale: completedSale, cashChange: receiptCashChange, completion: completion) { finish() }
                } else if let qrPayment {
                    QRPaymentView(
                        payment: qrPayment,
                        isRenewing: isSubmitting,
                        onPaid: { sale in Task { await complete(sale, cashChange: nil) } },
                        onPaidWithoutSale: {
                            withAnimation(.smooth) {
                                cart.moveQrShareToTransfer()
                                self.qrPayment = nil
                            }
                        },
                        onBack: { withAnimation(.smooth) { self.qrPayment = nil } },
                        onRenew: renewQrPayment
                    )
                    .id(qrPayment.id)
                } else {
                    form
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .errorAlert($errorMessage, title: errorTitle)
            .retryAlert($retryMessage, title: "Продажа могла пройти", retry: submit)
            .confirmationDialog("Очистить корзину?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) {
                    cart.clear()
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
            .sensoryFeedback(.success, trigger: completedSale != nil)
        }
        .interactiveDismissDisabled(isSubmitting || qrPayment != nil)
        .task {
            try? await reference.ensureQrPaymentsConfig()
            cart.dropQrIfUnavailable(qrEnabled: reference.qrPaymentsEnabled)
        }
        .onDisappear {
            if completedSale != nil { cart.clear() }
        }
    }

    private var title: String {
        if completedSale != nil { return "Продажа проведена" }
        return qrPayment == nil ? "Оформление" : "Оплата по QR"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if completedSale == nil && qrPayment == nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", role: .close) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Очистить корзину", systemImage: "trash", role: .destructive) { confirmsClear = true }
                    .disabled(cart.isEmpty)
            }
        }
    }

    private var form: some View {
        Form {
            CheckoutLinesSection()
            CheckoutClientSection()
            CheckoutAppointmentSection()
            CheckoutTotalsSection()
            CheckoutPaymentSection()
        }
        .safeAreaBar(edge: .bottom) {
            submitButton
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .overlay {
            if cart.isEmpty {
                ContentUnavailableView(
                    "Корзина пуста",
                    systemImage: "cart",
                    description: Text("Добавьте украшения или услугу на экране кассы.")
                )
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            ZStack {
                Group {
                    if cart.split.qr > 0 {
                        Label("Показать QR-код · \(Money.format(cart.split.qr))", systemImage: "qrcode")
                    } else {
                        Text("Провести продажу · \(Money.format(cart.total))")
                    }
                }
                .monospacedDigit()
                .opacity(isSubmitting ? 0 : 1)
                if isSubmitting { ProgressView().tint(.white) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!cart.canSubmit || isSubmitting)
        .accessibilityHint(submitHint)
    }

    private var submitHint: String {
        if !cart.isDiscountValid { return "Скидка больше суммы чека" }
        if !cart.isCashReceivedEnough { return "Получено меньше суммы к оплате" }
        if cart.remaining != 0 { return "Распределите сумму между способами оплаты" }
        return ""
    }

    /// Completes the appointment first (a bare sale would mark it completed without aftercare), then sells —
    /// or, with a QR share, shows the QR code and lets the server sell once the bank confirms the payment.
    private func submit() {
        let saleBody = cart.makeSaleBody()
        // The same cart resends the same key, so a retry after a lost response cannot create a second sale.
        let key = cart.saleIdempotencyKey(for: saleBody)
        let completeBody = cart.makeCompleteBody()
        let appointmentId = cart.appointmentId
        let cashChange = cart.cashChange
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            if let completeBody, let appointmentId {
                guard await completeAppointment(id: appointmentId, completeBody) else { return }
            }
            if saleBody.payments.qr > 0 {
                await startQrPayment(saleBody)
            } else {
                await createSale(saleBody, key: key, cashChange: cashChange)
            }
        }
    }

    /// Nothing is sold yet: a lost response only leaves an unseen code behind, so no idempotency key is needed.
    private func startQrPayment(_ body: SaleBody) async {
        do {
            let payment = try await api.createQrPayment(body)
            withAnimation(.smooth) { qrPayment = payment }
        } catch {
            showError(error.userMessage, title: "QR-код не создан")
            if completion != nil { await schedule.refreshVisible() }
        }
    }

    /// A fresh code for the same cart after the previous one expired.
    private func renewQrPayment() {
        let body = cart.makeSaleBody()
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            await startQrPayment(body)
        }
    }

    /// Idempotent on the server. On success the cart keeps the completed appointment, so a retry sends only the sale.
    private func completeAppointment(id: Int, _ body: CompleteBody) async -> Bool {
        do {
            let result = try await api.completeAppointment(id: id, body)
            cart.appointmentCompleted(result.appointment)
            completion = result
            return true
        } catch {
            showError(error.userMessage, title: "Запись не завершена")
            return false
        }
    }

    private func createSale(_ body: SaleBody, key: UUID, cashChange: Int?) async {
        do {
            await complete(try await api.createSale(body, idempotencyKey: key), cashChange: cashChange)
        } catch let error as APIError where error.isOutcomeUnknown {
            retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если продажа уже прошла, второй раз она не проведётся."
        } catch {
            showError(error.userMessage, title: Self.saleFailedTitle)
            // The appointment was completed even though the sale failed: show its new status in the schedule.
            if completion != nil { await schedule.refreshVisible() }
        }
    }

    private func complete(_ sale: Sale, cashChange: Int?) async {
        receiptCashChange = cashChange
        withAnimation(.smooth) {
            completedSale = sale
            qrPayment = nil
        }
        cart.recordCompletedSale()
        await shift.refresh()
        if sale.appointmentId != nil {
            await schedule.refreshVisible()
        }
    }

    private func showError(_ message: String, title: String) {
        errorTitle = title
        errorMessage = message
    }

    private func finish() {
        cart.clear()
        dismiss()
    }
}

#if DEBUG
#Preview {
    let state = PreviewData.appState()
    state.cart.prefill(from: PreviewData.appointments[0])
    state.cart.add(product: PreviewData.labret)
    return CheckoutView()
        .appEnvironment(state)
}
#endif
