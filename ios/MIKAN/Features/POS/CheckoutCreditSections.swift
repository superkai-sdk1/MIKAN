import SwiftUI

/// «Бонусы»: the client's balance, the most this receipt may take (`maxPaymentPercent`) and how much to spend.
/// Shown for a client of a studio with loyalty on; the server checks the same limits again.
struct CheckoutBonusSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        if cart.activeLoyalty != nil, cart.loyaltyRules?.loyaltyEnabled == true {
            Section {
                if cart.canSpendBonuses, cart.bonusLimit > 0 {
                    spendRows
                } else {
                    LabeledContent {
                        Text(BonusText.count(cart.bonusBalance)).monospacedDigit()
                    } label: {
                        Label("На счёте", systemImage: PaymentLine.bonusSymbol)
                    }
                }
            } header: {
                Text("Бонусы")
            } footer: {
                footer
            }
        }
    }

    /// The field keeps what was typed (so the text never disagrees with it); what is above the limit is not spent.
    @ViewBuilder
    private var spendRows: some View {
        @Bindable var cart = cart
        NumberField.money("Списать бонусами", value: $cart.bonusRequested, systemImage: PaymentLine.bonusSymbol)
        if cart.bonusRequested > cart.bonusApplied {
            Label("Спишется \(Money.format(cart.bonusApplied)) — больше в этом чеке нельзя", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .monospacedDigit()
        }
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { cart.spendMaxBonuses() }
            } label: {
                Text("Списать \(Money.format(cart.bonusLimit))").monospacedDigit().frame(maxWidth: .infinity)
            }
            .disabled(cart.bonusRequested == cart.bonusLimit)
            Button {
                withAnimation(.snappy) { cart.bonusRequested = 0 }
            } label: {
                Text("Не списывать").frame(maxWidth: .infinity)
            }
            .disabled(cart.bonusRequested == 0)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .sensoryFeedback(.selection, trigger: cart.bonusApplied)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if cart.canSpendBonuses, cart.bonusLimit > 0 {
                Text(BonusText.available(
                    balance: cart.bonusBalance,
                    limit: cart.bonusLimit,
                    percent: cart.loyaltyRules?.maxPaymentPercent ?? 0
                ))
            }
            if cart.sellsCertificate, cart.bonusBalance > 0 {
                Text("Чек с подарочным сертификатом оплачивается только деньгами.")
            }
            if let expiring = cart.activeLoyalty?.expiring, expiring.amount > 0 {
                Text(BonusText.expiring(expiring))
            }
            if cart.expectedCashback > 0 {
                Text("Бонусы за покупку: ≈ \(BonusText.count(cart.expectedCashback)).")
            }
        }
        .monospacedDigit()
    }
}

/// «Подарочные сертификаты»: certificates paying this receipt (code, balance, amount) and «Оплатить сертификатом».
struct CheckoutCertificatesSection: View {
    @Environment(CartStore.self) private var cart
    @State private var showsLookup = false

    var body: some View {
        if cart.acceptsCredits {
            Section {
                let amounts = cart.certificateAmounts
                ForEach(Array(cart.certificateCharges.enumerated()), id: \.element.id) { index, charge in
                    CertificateChargeRow(charge: charge, applied: amounts.indices.contains(index) ? amounts[index] : 0)
                }
                Button("Оплатить сертификатом", systemImage: PaymentLine.certificateSymbol) { showsLookup = true }
                    .disabled(cart.amountDue == 0)
            } header: {
                Text("Подарочные сертификаты")
            } footer: {
                if zip(cart.certificateCharges, cart.certificateAmounts).contains(where: { $0.1 < $0.0.amount }) {
                    Text("С сертификата спишется не больше его остатка и того, что осталось оплатить.")
                }
            }
            .sheet(isPresented: $showsLookup) {
                CertificateLookupSheet()
            }
        } else if !cart.certificateCharges.isEmpty {
            Section {
                Label("Чек с подарочным сертификатом оплачивается только деньгами — выбранные сертификаты не спишутся.", systemImage: "info.circle")
                    .font(.subheadline)
            }
        }
    }
}

private struct CertificateChargeRow: View {
    @Environment(CartStore.self) private var cart
    let charge: CertificateCharge
    /// What it pays in this receipt.
    let applied: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(charge.code, systemImage: PaymentLine.certificateSymbol)
                    .font(.body.weight(.medium).monospaced())
                Spacer(minLength: 8)
                Button("Убрать сертификат", systemImage: "xmark.circle.fill") {
                    withAnimation(.snappy) { cart.removeCertificateCharge(code: charge.code) }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
            }
            Text("Остаток \(Money.format(charge.balance)) · действует \(CertificateText.validity(charge.expiresAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            // Keeps what was typed; above the balance or the unpaid rest it is not spent.
            NumberField.money("Списать", value: Binding(
                get: { charge.amount },
                set: { cart.setCertificateAmount($0, code: charge.code) }
            ))
            .font(.subheadline)
            if applied < charge.amount {
                Label("Спишется \(Money.format(applied))", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

/// «🎂 Скидка именинника 10%» under the discount field while the client is inside their birthday window.
struct CheckoutBirthdayDiscountRow: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        if let discount = cart.birthdayDiscount, cart.birthdayDiscountAmount > 0 {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🎂 Скидка именинника \(discount.percent)%").font(.subheadline.weight(.semibold))
                    Text(subtitle(discount)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 8)
                if cart.isBirthdayDiscountApplied {
                    Label("Применена", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Скидка применена")
                } else {
                    Button("Применить") {
                        withAnimation(.snappy) { cart.applyBirthdayDiscount() }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func subtitle(_ discount: BirthdayDiscount) -> String {
        let amount = "−\(Money.format(cart.birthdayDiscountAmount))"
        guard let until = CalendarDay.date(from: discount.until) else { return amount }
        return "\(amount) · действует до \(DateText.dayMonth(until))"
    }
}

/// «Бонусы −500 ₽», «Сертификат −1 000 ₽» in the totals, before «К оплате».
struct CheckoutCreditRows: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        if cart.bonusApplied > 0 {
            creditRow(PaymentLine.bonusTitle, symbol: PaymentLine.bonusSymbol, amount: cart.bonusApplied)
        }
        if cart.certificatesApplied > 0 {
            creditRow(PaymentLine.certificateTitle, symbol: PaymentLine.certificateSymbol, amount: cart.certificatesApplied)
        }
    }

    private func creditRow(_ title: String, symbol: String, amount: Int) -> some View {
        LabeledContent {
            Text(Money.format(-amount))
                .monospacedDigit()
                .foregroundStyle(.green)
                .contentTransition(.numericText(value: Double(amount)))
                .animation(.snappy, value: amount)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

/// «Чек полностью оплачен предоплатой и бонусами» when nothing is left for the payment methods.
nonisolated enum CheckoutPaidText {
    static func fullyPaid(deposit: Int, bonus: Int, certificate: Int) -> String {
        let parts = [
            deposit > 0 ? "предоплатой" : nil,
            bonus > 0 ? "бонусами" : nil,
            certificate > 0 ? "сертификатом" : nil,
        ].compactMap { $0 }
        guard !parts.isEmpty else { return "Чек полностью оплачен" }
        return "Чек полностью оплачен " + parts.formatted(.list(type: .and).locale(.app))
    }
}
