import SwiftUI

struct CheckoutLinesSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        @Bindable var cart = cart
        Section("Позиции") {
            ForEach($cart.lines) { $line in
                CheckoutLineRow(line: $line)
            }
            .onDelete { cart.remove(at: $0) }
        }
    }
}

private struct CheckoutLineRow: View {
    @Binding var line: CartLine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: line.productId == nil ? "sparkle" : "shippingbox")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(line.name).font(.headline)
                Spacer()
                MoneyText(line.total).font(.headline)
            }
            Stepper(value: $line.quantity, in: 1...999) {
                Text("Количество: \(line.quantity)").monospacedDigit()
            }
            NumberField.money("Цена за шт.", value: $line.unitPrice)
            if line.exceedsStock, let stock = line.stock {
                Label("На складе только \(stock)", systemImage: "exclamationmark.triangle.fill")
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
                        InitialsAvatar(name: client.name, size: 32)
                        Text(client.name)
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
        } footer: {
            if !cart.isDiscountValid {
                Text("Скидка не может быть больше суммы чека.").foregroundStyle(.red)
            }
        }
    }
}

struct PaymentSplitSection: View {
    @Environment(CartStore.self) private var cart
    var methods: [PaymentMethod] = PaymentMethod.allCases

    /// Four labels do not fit one row on a phone: two rows of two.
    private var oneTapColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: methods.count > 3 ? 2 : max(methods.count, 1))
    }

    var body: some View {
        @Bindable var cart = cart
        Section {
            ForEach(methods) { method in
                NumberField.money(method.title, value: $cart.split[method], systemImage: method.symbol)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(cart.deposit > 0 ? "Остаток одним способом" : "Всё одним способом")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: oneTapColumns, spacing: 8) {
                    ForEach(methods) { method in
                        Button {
                            withAnimation(.snappy) { cart.applyOneTap(method) }
                        } label: {
                            Label(method.oneTapTitle, systemImage: method.symbol)
                                .labelStyle(.titleOnly)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .accessibilityLabel(cart.deposit > 0 ? "Остаток \(method.instrumental)" : "Всё \(method.instrumental)")
                    }
                }
            }
            .padding(.vertical, 4)
            RemainingIndicator(remaining: cart.remaining)
        } header: {
            Text("Оплата")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if cart.deposit > 0 {
                    Text("Предоплата \(Money.format(cart.deposit)) уже получена и учтена в «Перевод». Если её вносили иначе — перенесите сумму в нужный способ.")
                }
                if cart.split.qr > 0 {
                    Text("Сумму «QR-код» клиент оплатит через СБП по коду на экране. Продажа проведётся, как только банк подтвердит оплату.")
                }
            }
        }
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

/// Receipt summary shown after a successful sale.
struct SaleReceiptView: View {
    let sale: Sale
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
            SaleItemsSection(sale: sale)
            SalePaymentsSection(payments: sale.payments)
            if let client = sale.client {
                Section("Клиент") { Text(client.name) }
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
                        Text(item.name)
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

struct SalePaymentsSection: View {
    let payments: Payments

    var body: some View {
        Section("Оплата") {
            ForEach(PaymentMethod.allCases) { method in
                let amount = PaymentSplit(payments)[method]
                if amount > 0 {
                    LabeledContent {
                        MoneyText(amount)
                    } label: {
                        Label(method.title, systemImage: method.symbol)
                    }
                }
            }
        }
    }
}
