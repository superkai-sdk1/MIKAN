import SwiftUI

/// «Запись завершена»: the memos scheduled, what was taken from the warehouse (shortages in orange) and payment.
struct CompletionSuccessView: View {
    let appointment: Appointment
    let scheduledMessages: Int
    let consumption: Consumption
    /// Units of the consumables by product id («шт» when unknown).
    let units: [Int: String]
    let onPay: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: true)
                        .accessibilityHidden(true)
                        .padding(.top, 32)
                    Text("Запись завершена")
                        .font(.title2.weight(.bold))
                    if scheduledMessages > 0 {
                        Text("Запланировано сообщений по уходу: \(scheduledMessages)")
                            .foregroundStyle(.secondary)
                    }
                    if consumption != Consumption() {
                        ConsumptionSummaryCard(consumption: consumption, units: units)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 12) {
                if !appointment.isPaid {
                    Button(action: onPay) {
                        Label("Принять оплату · \(Money.format(appointment.price))", systemImage: "creditcard.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                } else {
                    Label("Оплачено", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                Button(action: onDone) {
                    Text("Готово").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(24)
    }
}

/// What completing the visit took from the warehouse; norms the stock could not cover in orange.
private struct ConsumptionSummaryCard: View {
    let consumption: Consumption
    let units: [Int: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Списано со склада", systemImage: CatalogSection.consumable.symbol)
                .font(.headline)
            if consumption.used.isEmpty {
                Text("Ничего не списано").foregroundStyle(.secondary)
            }
            ForEach(consumption.used, id: \.productId) { item in
                HStack {
                    Text(item.productName)
                    Spacer(minLength: 8)
                    Text("\(item.quantity) \(unit(item.productId))")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            if !consumption.shortages.isEmpty {
                Divider()
                ForEach(consumption.shortages, id: \.productId) { shortage in
                    Label(
                        VisitConsumption.shortageText(shortage, unit: unit(shortage.productId)),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                }
                Text("Не хватило на складе — пополните остатки, недостающее не списано.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func unit(_ productId: Int) -> String { units[productId] ?? "шт" }
}

#if DEBUG
#Preview {
    CompletionSuccessView(
        appointment: PreviewData.appointments[0],
        scheduledMessages: 3,
        consumption: Consumption(
            used: [Consumption.Used(productId: 3, productName: "Иглы 1.2 мм", quantity: 2)],
            shortages: [Consumption.Shortage(productId: 9, productName: "Перчатки", needed: 2, deducted: 1)]
        ),
        units: [3: "шт"]
    ) {} onDone: {}
}
#endif
