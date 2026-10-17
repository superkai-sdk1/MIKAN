import SwiftUI

/// What is still to pay, for whom and when.
struct DepositCollectHeader: View {
    let appointment: Appointment

    private var missing: Int { DepositSummary.missing(appointment) }

    private var caption: String {
        if missing == 0 { return "Предоплата внесена" }
        return appointment.deposit > 0 ? "Осталось внести" : "Нужна предоплата"
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(caption, systemImage: missing > 0 ? DepositStyle.waitingSymbol : DepositStyle.heldSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(missing > 0 ? Color.orange : Color.green)
                MoneyText(missing > 0 ? missing : appointment.deposit)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("\(appointment.client.fullName) · \(DateText.dayMonth(appointment.startsAt)), \(DateText.time(appointment.startsAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if appointment.deposit > 0, appointment.depositRequired > 0 {
                    Text(DepositSummary.progressText(held: appointment.deposit, required: appointment.depositRequired))
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

/// «Клиент оплатил»: the way the money was taken, then one clear button.
struct DepositReceiveSection: View {
    @Binding var method: PaymentMethod
    let amount: Int
    let isRunning: Bool
    let onReceive: () -> Void

    var body: some View {
        Section {
            Picker("Способ", selection: $method) {
                ForEach(DepositCollectView.receiveMethods) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Клиент оплатил")
        } footer: {
            Text(method == .cash
                ? "Наличные попадут в открытую кассовую смену."
                : "Отмечайте, когда деньги уже у студии.")
        }
        Section {
            Button(action: onReceive) {
                ZStack {
                    Text(amount > 0 ? "Принять \(Money.format(amount)) \(method.instrumental)" : "Принять \(method.instrumental)")
                        .monospacedDigit()
                        .opacity(isRunning ? 0 : 1)
                    if isRunning { ProgressView().tint(.white) }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(amount <= 0)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }
}

/// «Оплата по СБП»: a code on the screen, a link sent by the bot or shared by staff.
struct DepositSBPSection: View {
    let link: QrPayment?
    let linkProblem: String?
    let pollProblem: String?
    let canStart: Bool
    let running: DepositRequest?
    let shareText: (QrPayment) -> String
    let onScreen: () -> Void
    let onTelegram: () -> Void
    let onLink: () -> Void

    private var pendingLink: QrPayment? { link?.status == .pending ? link : nil }

    var body: some View {
        Section {
            actionButton("QR-код на экране", systemImage: "qrcode", request: .screen, action: onScreen)
            actionButton("Отправить в Telegram", systemImage: "paperplane", request: .telegram, action: onTelegram)
            if let pendingLink {
                linkStatus(pendingLink)
                ShareLink(item: shareText(pendingLink)) {
                    Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                }
            } else {
                if link?.status == .expired {
                    Label("Срок ссылки истёк — создайте новую", systemImage: "clock.badge.xmark")
                        .foregroundStyle(.secondary)
                }
                actionButton("Поделиться ссылкой", systemImage: "square.and.arrow.up", request: .link, action: onLink)
            }
            if let linkProblem {
                Label(linkProblem, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Оплата по СБП")
        } footer: {
            Text("QR-код на экране действует 10 минут, ссылка — до начала записи. Когда клиент оплатит, предоплата отметится сама.")
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        request: DepositRequest,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                if running == request { ProgressView() }
            }
        }
        .disabled(!canStart)
    }

    private func linkStatus(_ payment: QrPayment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if payment.sentAt != nil {
                Label("Ссылка на \(Money.format(payment.amount)) отправлена клиенту", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Ссылка на \(Money.format(payment.amount)) готова", systemImage: "link")
            }
            Text("Действует до \(DateText.dateTime(payment.expiresAt)) · ждём оплату")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let pollProblem {
                Text(pollProblem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

/// «Предоплата внесена»: how much and how, what is left.
struct DepositDoneView: View {
    let receipt: DepositReceipt
    let appointment: Appointment
    let reloadProblem: String?
    /// «Принять ещё» while part of the prepayment is still missing.
    let onMore: (() -> Void)?
    let onDone: () -> Void

    private var missing: Int { DepositSummary.missing(appointment) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .accessibilityHidden(true)
                Text("Предоплата внесена")
                    .font(.title2.weight(.bold))
                Text("\(Money.format(receipt.amount)) \(receipt.method.instrumental)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if appointment.depositRequired > 0 {
                    Text(DepositSummary.progressText(held: appointment.deposit, required: appointment.depositRequired))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if missing > 0 {
                    Text("Осталось внести \(Money.format(missing))")
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
                if let issue = receipt.issue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let reloadProblem {
                    Label(reloadProblem, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: onDone) {
                    Text("Готово").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                if let onMore, missing > 0 {
                    Button("Принять ещё \(Money.format(missing))", action: onMore)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
