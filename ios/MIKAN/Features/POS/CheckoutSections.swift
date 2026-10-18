import SwiftUI

struct CheckoutLinesSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        @Bindable var cart = cart
        Section("Позиции") {
            ForEach($cart.lines) { $line in
                CheckoutLineRow(line: $line, stockWarning: cart.stockWarning(for: line))
            }
            .onDelete { cart.remove(at: $0) }
        }
    }
}

private struct CheckoutLineRow: View {
    @Binding var line: CartLine
    /// Set when all lines of the size together exceed its stock.
    let stockWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: line.productId == nil ? "sparkle" : "shippingbox")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SizedItemTitle(name: line.name, size: line.sizeName).font(.headline)
                Spacer()
                MoneyText(line.total).font(.headline)
            }
            Stepper(value: $line.quantity, in: 1...999) {
                Text("Количество: \(line.quantity)").monospacedDigit()
            }
            NumberField.money("Цена за шт.", value: $line.unitPrice)
            if let stockWarning {
                Label(stockWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CheckoutClientSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        @Bindable var cart = cart
        Section("Клиент") {
            NavigationLink {
                ClientPickerView(selection: $cart.client)
            } label: {
                if let client = cart.client {
                    HStack(spacing: 12) {
                        InitialsAvatar(name: client.fullName, size: 32)
                        Text(client.fullName)
                    }
                } else {
                    Label("Без клиента", systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary)
                }
            }
            if cart.client != nil {
                Button("Убрать клиента", role: .destructive) { cart.client = nil }
            }
        }
    }
}

struct CheckoutTotalsSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        @Bindable var cart = cart
        Section {
            LabeledContent("Подытог") { MoneyText(cart.subtotal) }
            NumberField.money("Скидка", value: $cart.discount, systemImage: "tag")
            LabeledContent {
                MoneyText(cart.total).font(.title3.weight(.bold))
            } label: {
                Text("Итого").font(.title3.weight(.bold))
            }
            if cart.depositApplied > 0 {
                CheckoutDepositRows()
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !cart.isDiscountValid {
                    Text("Скидка не может быть больше суммы чека.").foregroundStyle(.red)
                }
                if cart.depositRemainder > 0 {
                    Text("Остаток предоплаты \(Money.format(cart.depositRemainder)) останется за записью — верните его клиенту в карточке записи.")
                }
            }
        }
    }
}

/// «Предоплата −2 000 ₽ · внесена переводом 15 октября» and «К оплате» — what is left after the prepayment.
private struct CheckoutDepositRows: View {
    @Environment(CartStore.self) private var cart

    private var receivedNote: String? {
        ReceiptDraft.depositReceivedNote(cart.appointment?.depositOperations ?? [])
    }

    var body: some View {
        LabeledContent {
            Text(Money.format(-cart.depositApplied))
                .monospacedDigit()
                .foregroundStyle(.green)
        } label: {
            Label(PaymentLine.depositTitle, systemImage: PaymentLine.depositSymbol)
            if let receivedNote {
                Text(receivedNote)
            }
        }
        LabeledContent {
            MoneyText(cart.amountDue)
                .fontWeight(.semibold)
                .contentTransition(.numericText(value: Double(cart.amountDue)))
                .animation(.snappy, value: cart.amountDue)
        } label: {
            Text("К оплате").fontWeight(.semibold)
        }
    }
}

/// «Запись»: completes the appointment (and schedules aftercare) right before the sale.
struct CheckoutAppointmentSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        @Bindable var cart = cart
        if let appointment = cart.appointment, cart.hasPendingAppointment {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appointment.displayTitle).font(.headline)
                    Text("\(DateText.dateTime(appointment.startsAt)) · \(appointment.master.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Toggle("Завершить запись при оплате", isOn: $cart.completesAppointment)
                Toggle("Отправить памятку по уходу", isOn: Binding(
                    get: { cart.sendsAftercare && cart.canSendAftercare && cart.completesAppointment },
                    set: { cart.sendsAftercare = $0 }
                ))
                .disabled(!cart.canSendAftercare || !cart.completesAppointment)
            } header: {
                Text("Запись")
            } footer: {
                if !cart.completesAppointment {
                    Text("После оплаты запись всё равно отметится завершённой, но без памятки по уходу.")
                } else if !cart.canSendAftercare {
                    Text("Клиент не подключил Telegram-бота")
                } else if cart.sendsAftercare {
                    Text("Памятка по шаблону услуги придёт клиенту в Telegram.")
                }
            }
        }
    }
}

/// Receipt summary shown after a successful sale.
struct SaleReceiptView: View {
    let sale: Sale
    /// Change for the cash the client handed over (checkout only, not stored on the server).
    var cashChange: Int?
    /// Prepayment that stays held for the appointment because it was larger than the receipt.
    var depositRemainder = 0
    /// Set when this checkout completed the appointment before the sale.
    var completion: CompleteAppointmentResult?
    let onDone: () -> Void

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: sale.id)
                        .accessibilityHidden(true)
                    Text("Продажа №\(sale.number)").font(.title2.weight(.bold))
                    MoneyText(sale.total).font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text(DateText.dateTime(sale.createdAt)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            if let cashChange, cashChange > 0 {
                Section {
                    LabeledContent {
                        MoneyText(cashChange).font(.title2.weight(.bold))
                    } label: {
                        Label("Сдача", systemImage: "banknote").font(.title3.weight(.semibold))
                    }
                }
            }
            SaleItemsSection(sale: sale)
            SalePaymentsSection(payments: sale.payments)
            if depositRemainder > 0 {
                Section {
                    Label(
                        "Остаток предоплаты \(Money.format(depositRemainder)) остался за записью — верните его клиенту в карточке записи.",
                        systemImage: "info.circle"
                    )
                    .font(.subheadline)
                }
            }
            if let client = sale.client {
                Section("Клиент") { Text(client.fullName) }
            }
            if let completion {
                Section("Запись") {
                    Label("Запись завершена", systemImage: "checkmark.circle")
                    if completion.scheduledMessages > 0 {
                        Label(
                            "Памятка по уходу: " + Plural.count(completion.scheduledMessages, one: "сообщение", few: "сообщения", many: "сообщений"),
                            systemImage: "paperplane"
                        )
                    }
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            Button(action: onDone) {
                Text("Готово").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

struct SaleItemsSection: View {
    let sale: Sale

    var body: some View {
        Section("Позиции") {
            ForEach(sale.items) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        SizedItemTitle(name: item.name, size: item.variantName)
                        Text("\(item.quantity) × \(Money.format(item.price))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    MoneyText(item.total)
                }
                .accessibilityElement(children: .combine)
            }
            if sale.discount > 0 {
                LabeledContent("Подытог") { MoneyText(sale.subtotal) }
                LabeledContent("Скидка") { Text("−" + Money.format(sale.discount)).monospacedDigit() }
            }
            LabeledContent("Итого") { MoneyText(sale.total).fontWeight(.bold) }
        }
    }
}

/// How a sale was paid: the methods and the part covered by the appointment's prepayment.
struct SalePaymentsSection: View {
    let payments: Payments

    var body: some View {
        Section("Оплата") {
            ForEach(payments.paymentLines) { line in
                LabeledContent {
                    MoneyText(line.amount)
                } label: {
                    Label(line.title, systemImage: line.symbol)
                }
            }
        }
    }
}
