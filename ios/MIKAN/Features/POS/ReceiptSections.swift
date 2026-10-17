import SwiftUI

/// Who the receipt is for: the appointment it pays (with «Отвязать»), the client, or «Добавить клиента».
struct ReceiptHeaderSection: View {
    @Environment(AppState.self) private var appState
    @Environment(CartStore.self) private var cart

    var body: some View {
        Section {
            if let appointment = cart.appointment {
                ReceiptAppointmentBanner(appointment: appointment, deposit: cart.deposit, applied: cart.depositApplied) {
                    withAnimation(.snappy) { cart.detachAppointment() }
                }
            } else if let client = cart.client {
                ReceiptClientRow(client: client, onChange: pickClient) {
                    withAnimation(.snappy) { cart.client = nil }
                }
            } else {
                Button(action: pickClient) {
                    HStack {
                        Label("Добавить клиента", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
            }
        }
    }

    private func pickClient() {
        appState.posPath.append(.clientPicker)
    }
}

private struct ReceiptAppointmentBanner: View {
    let appointment: Appointment
    /// Prepayment held for the appointment and the part of it this receipt applies.
    let deposit: Int
    let applied: Int
    let onDetach: () -> Void

    private var masterColor: Color { .master(appointment.master.color) }

    private var details: String {
        ReceiptDraft.appointmentDetails(master: appointment.master.name, deposit: deposit, applied: applied)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(masterColor)
                .frame(width: 34, height: 34)
                .background(masterColor.opacity(0.15), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ReceiptDraft.appointmentBanner(appointment))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Отвязать", action: onDetach)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(deposit > 0
                    ? "Чек останется, но не будет привязан к записи, предоплата останется за записью"
                    : "Чек останется, но не будет привязан к записи")
        }
        .padding(.vertical, 2)
    }
}

private struct ReceiptClientRow: View {
    let client: ClientRef
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onChange) {
                HStack(spacing: 12) {
                    InitialsAvatar(name: client.fullName, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Клиент").font(.caption).foregroundStyle(.secondary)
                        Text(client.fullName).font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Клиент: \(client.fullName)")
            .accessibilityHint("Выбрать другого клиента")

            Button("Убрать клиента", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
        }
    }
}

/// Editable receipt lines: unit price, quantity, swipe to delete.
struct ReceiptLinesSection: View {
    @Environment(CartStore.self) private var cart

    var body: some View {
        @Bindable var cart = cart
        Section {
            if cart.lines.isEmpty {
                Label("Добавьте украшение из каталога ниже или услугу кнопкой «Услуга».", systemImage: "cart")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($cart.lines) { $line in
                    ReceiptLineRow(line: $line)
                }
                .onDelete { offsets in
                    withAnimation(.snappy) { cart.remove(at: offsets) }
                }
            }
        } header: {
            Text("Позиции")
        } footer: {
            if !cart.lines.isEmpty {
                Text("Смахните позицию влево, чтобы удалить её из чека.")
            }
        }
    }
}

private struct ReceiptLineRow: View {
    @Binding var line: CartLine

    private static let serviceQuantityLimit = 99

    /// Products cannot be sold beyond stock (the server answers `insufficient_stock`).
    private var quantityRange: ClosedRange<Int> {
        guard let stock = line.stock else { return 1...Self.serviceQuantityLimit }
        return 1...max(1, stock, line.quantity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: line.productId == nil ? "hands.and.sparkles" : "sparkles")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(line.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                MoneyText(line.total)
                    .font(.body.weight(.semibold))
                    .contentTransition(.numericText(value: Double(line.total)))
                    .animation(.snappy, value: line.total)
            }
            NumberField.money("Цена за шт.", value: $line.unitPrice)
                .font(.subheadline)
            Stepper(value: $line.quantity, in: quantityRange) {
                Text("Количество: \(line.quantity)")
                    .font(.subheadline)
                    .monospacedDigit()
            }
            if line.exceedsStock, let stock = line.stock {
                Label("На складе только \(stock) шт", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
