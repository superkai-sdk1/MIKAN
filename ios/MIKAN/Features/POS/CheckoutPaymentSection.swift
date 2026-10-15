import SwiftUI

/// «Оплата»: one method with the amount computed from the total (no typing), or a manual split.
struct CheckoutPaymentSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        Section {
            PaymentModePicker()
            switch cart.paymentMode {
            case .single(let method):
                SinglePaymentRows(method: method)
            case .split:
                SplitPaymentRows()
            }
        } header: {
            Text("Оплата")
        } footer: {
            if cart.deposit > cart.total {
                Text("Предоплата \(Money.format(cart.deposit)) больше суммы чека — в чек попадёт \(Money.format(cart.depositApplied)).")
            } else if cart.paymentMode == .split, cart.depositApplied > 0 {
                Text("Предоплата \(Money.format(cart.depositApplied)) уже получена и учтена в «Перевод».")
            }
        }
    }
}

private struct PaymentModePicker: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        Picker("Способ оплаты", selection: Binding(
            get: { cart.paymentMode },
            set: { mode in withAnimation(.snappy) { cart.selectPaymentMode(mode) } }
        )) {
            ForEach(PaymentMode.choices, id: \.self) { mode in
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
        if cart.amountDue == 0, cart.depositApplied > 0 {
            Label("Чек полностью оплачен предоплатой", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
        } else {
            AmountDueRow(method: method, amount: cart.amountDue)
        }
        if cart.depositApplied > 0 {
            Label("Предоплата \(Money.format(cart.depositApplied)) (перевод)", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
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

    var body: some View {
        @Bindable var cart = cart
        ForEach(PaymentMethod.allCases) { method in
            NumberField.money(method.title, value: $cart.manualSplit[method], systemImage: method.symbol)
        }
        if cart.remaining != 0 {
            RemainderChips(remaining: cart.remaining)
        }
        RemainingIndicator(remaining: cart.remaining)
    }
}

/// «Остаток картой» etc.: moves what is left (or overpaid) into one method with a tap.
private struct RemainderChips: View {
    @Environment(CartStore.self) private var cart
    let remaining: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(remaining > 0 ? "Добавить остаток \(Money.format(remaining)):" : "Убрать лишние \(Money.format(-remaining)) из:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 8) {
                ForEach(PaymentMethod.allCases) { method in
                    Button {
                        withAnimation(.snappy) { cart.fillRemaining(with: method) }
                    } label: {
                        Text(method.instrumental.capitalized).frame(maxWidth: .infinity)
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
