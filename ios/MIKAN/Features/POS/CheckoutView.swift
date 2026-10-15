import SwiftUI

/// Checkout sheet: lines, client, discount, payment split → «Провести продажу» → receipt.
struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    @Environment(ShiftStore.self) private var shift
    @Environment(ScheduleStore.self) private var schedule

    @State private var completedSale: Sale?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var confirmsClear = false
    @State private var retryMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let completedSale {
                    SaleReceiptView(sale: completedSale) { finish() }
                } else {
                    form
                }
            }
            .navigationTitle(completedSale == nil ? "Оформление" : "Продажа проведена")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .errorAlert($errorMessage, title: "Продажа не проведена")
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
        .interactiveDismissDisabled(isSubmitting)
        .onDisappear {
            if completedSale != nil { cart.clear() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if completedSale == nil {
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
            CheckoutTotalsSection()
            PaymentSplitSection()
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
                Text("Провести продажу · \(Money.format(cart.total))")
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
        .accessibilityHint(cart.canSubmit ? "" : "Распределите сумму между способами оплаты")
    }

    private func submit() {
        let body = cart.makeSaleBody()
        // The same cart resends the same key, so a retry after a lost response cannot create a second sale.
        let key = cart.saleIdempotencyKey(for: body)
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                await complete(try await api.createSale(body, idempotencyKey: key))
            } catch let error as APIError where error.isOutcomeUnknown {
                retryMessage = "Связь прервалась до ответа сервера. Нажмите «Повторить» — если продажа уже прошла, второй раз она не проведётся."
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    private func complete(_ sale: Sale) async {
        withAnimation(.smooth) { completedSale = sale }
        await shift.refresh()
        if sale.appointmentId != nil {
            await schedule.refreshVisible()
        }
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
