import SwiftUI

/// «Оплата»: what is due now (the total minus the applied prepayment) paid by one method with the amount computed
/// automatically (no typing), or a manual split. Methods: cash, transfer and — when the server has Tochka
/// configured — an SBP QR code. A receipt covered by the prepayment needs no method at all.
struct CheckoutPaymentSection: View {
    @Environment(CartStore.self) private var cart
    @Environment(ReferenceStore.self) private var reference

    /// QR shows once the server says it takes QR payments, or while the cart already uses it.
    private var qrShown: Bool { reference.qrPaymentsEnabled || cart.split.qr > 0 }

    var body: some View {
        Section {
            if cart.isPaidInFull {
                Label(
                    CheckoutPaidText.fullyPaid(
                        deposit: cart.depositApplied, bonus: cart.bonusApplied, certificate: cart.certificatesApplied
                    ),
                    systemImage: "checkmark.seal.fill"
                )
                .font(.headline)
                .foregroundStyle(.green)
            } else {
                PaymentModePicker(qrEnabled: qrShown)
                switch cart.paymentMode {
                case .single(let method):
                    SinglePaymentRows(method: method)
                case .split:
                    SplitPaymentRows(methods: PaymentMethod.accepted(qrEnabled: qrShown))
                }
            }
        } header: {
            Text("Оплата")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if cart.paymentMode == .split, cart.depositApplied + cart.creditsApplied > 0, !cart.isPaidInFull {
                    Text("Распределите \(Money.format(cart.amountDue)) — сумму к оплате без предоплаты, бонусов и сертификатов.")
                }
                if cart.split.qr > 0 {
                    Text("Клиент оплатит \(Money.format(cart.split.qr)) через СБП по QR-коду на экране. Продажа проведётся, как только банк подтвердит оплату.")
                }
            }
        }
    }
}

private struct PaymentModePicker: View {
    @Environment(CartStore.self) private var cart
    let qrEnabled: Bool

    var body: some View {
        Picker("Способ оплаты", selection: Binding(
            get: { cart.paymentMode },
            set: { mode in withAnimation(.snappy) { cart.selectPaymentMode(mode) } }
        )) {
            ForEach(PaymentMode.choices(qrEnabled: qrEnabled), id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: cart.paymentMode)
    }
}

// MARK: - One method

private struct SinglePaymentRows: View {
    @Environment(CartStore.self) private var cart
    let method: PaymentMethod

    var body: some View {
        AmountDueRow(method: method, amount: cart.amountDue)
        if method == .cash, cart.amountDue > 0 {
            CashTenderRows()
        }
    }
}

private struct AmountDueRow: View {
    let method: PaymentMethod
    let amount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("К оплате \(method.instrumental)", systemImage: method.symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money.format(amount))
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(amount)))
                .animation(.snappy, value: amount)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("К оплате \(method.instrumental): \(Money.format(amount))")
    }
}

/// Optional «received» amount → change. Display only: the sale always records the exact due amount.
private struct CashTenderRows: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        @Bindable var cart = cart
        NumberField.optionalMoney("Получено от клиента", value: $cart.cashReceived)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(CashTender.suggestions(for: cart.amountDue), id: \.self) { amount in
                    Button {
                        cart.cashReceived = amount
                    } label: {
                        Text(amount == cart.amountDue ? "Без сдачи" : Money.format(amount)).monospacedDigit()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(cart.cashReceived == amount ? .accentColor : .secondary)
                    .accessibilityLabel(amount == cart.amountDue ? "Получено без сдачи" : "Получено \(Money.format(amount))")
                }
            }
        }
        .scrollIndicators(.hidden)
        changeRow
    }

    @ViewBuilder
    private var changeRow: some View {
        if let change = cart.cashChange {
            LabeledContent {
                MoneyText(change)
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText(value: Double(change)))
                    .animation(.snappy, value: change)
            } label: {
                Text("Сдача").font(.title3.weight(.semibold))
            }
        } else if let received = cart.cashReceived, !cart.isCashReceivedEnough {
            Label("Не хватает \(Money.format(cart.amountDue - received))", systemImage: "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .monospacedDigit()
        }
    }
}

// MARK: - Split

private struct SplitPaymentRows: View {
    @Environment(CartStore.self) private var cart
    let methods: [PaymentMethod]

    var body: some View {
        @Bindable var cart = cart
        ForEach(methods) { method in
            NumberField.money(method.title, value: $cart.manualSplit[method], systemImage: method.symbol)
        }
        if cart.remaining != 0 {
            RemainderChips(methods: methods, remaining: cart.remaining)
        }
        RemainingIndicator(remaining: cart.remaining)
    }
}

/// «Остаток наличными» etc.: moves what is left (or overpaid) into one method with a tap.
private struct RemainderChips: View {
    @Environment(CartStore.self) private var cart
    let methods: [PaymentMethod]
    let remaining: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(remaining > 0 ? "Добавить остаток \(Money.format(remaining)):" : "Убрать лишние \(Money.format(-remaining)) из:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 8) {
                ForEach(methods) { method in
                    Button {
                        withAnimation(.snappy) { cart.fillRemaining(with: method) }
                    } label: {
                        Text(method.instrumentalTitle).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(remaining < 0 && cart.manualSplit[method] == 0)
                    .accessibilityLabel(remaining > 0 ? "Остаток \(method.instrumental)" : "Убрать лишнее из «\(method.title)»")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RemainingIndicator: View {
    let remaining: Int

    var body: some View {
        Group {
            if remaining == 0 {
                Label("Сумма распределена", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if remaining > 0 {
                Label("Осталось распределить: \(Money.format(remaining))", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Лишние \(Money.format(-remaining)) — уменьшите оплату", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .contentTransition(.numericText())
        .animation(.snappy, value: remaining)
    }
}
