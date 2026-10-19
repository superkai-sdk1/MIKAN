import SwiftUI

/// «Оплатить сертификатом»: type or paste the code, look it up (`GET /certificates/code/:code`), see its balance and
/// choose how much of it pays this receipt.
struct CertificateLookupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart

    @State private var code = ""
    @State private var certificate: GiftCertificate?
    @State private var amount = 0
    @State private var isSearching = false
    @State private var errorMessage: String?
    /// The code of the last lookup, so a complete code is looked up once while typing.
    @State private var lookedUp: String?
    @FocusState private var focusesCode: Bool

    private var unavailableReason: String? { certificate.flatMap { CertificateText.unavailableReason($0) } }
    private var maxAmount: Int {
        certificate.map { cart.suggestedCertificateAmount(balance: $0.balance, code: $0.code) } ?? 0
    }
    private var canApply: Bool { certificate != nil && unavailableReason == nil && amount > 0 && amount <= maxAmount }
    private var isOverLimit: Bool { amount > maxAmount }

    var body: some View {
        NavigationStack {
            Form {
                codeSection
                if let certificate {
                    CertificateSummarySection(certificate: certificate)
                    if let unavailableReason {
                        Section {
                            Label(unavailableReason, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    } else {
                        amountSection
                    }
                }
            }
            .navigationTitle("Оплата сертификатом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить", action: apply).disabled(!canApply)
                }
            }
            .errorAlert($errorMessage, title: "Сертификат не найден")
            .onAppear { focusesCode = true }
            .onChange(of: code) { _, newValue in
                if CertificateCode.isComplete(newValue), CertificateCode.normalize(newValue) != lookedUp { lookup() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var codeSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("MIKAN-XXXX-XXXX", text: $code)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusesCode)
                    .submitLabel(.search)
                    .onSubmit(lookup)
                // SwiftUI may call this off the main thread: hop back before touching the field.
                PasteButton(payloadType: String.self) { @Sendable strings in
                    guard let pasted = strings.first else { return }
                    Task { @MainActor in code = pasted }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
            Button(action: lookup) {
                HStack {
                    Label("Найти", systemImage: "magnifyingglass")
                    if isSearching {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(CertificateCode.normalize(code) == nil || isSearching)
        } footer: {
            Text("Введите или вставьте код с сертификата — регистр и дефисы не важны.")
        }
    }

    private var amountSection: some View {
        Section {
            NumberField.money("Списать", value: $amount, systemImage: PaymentLine.certificateSymbol)
        } footer: {
            Text("Не больше остатка сертификата и суммы к оплате — \(Money.format(maxAmount)).")
                .foregroundStyle(isOverLimit ? .red : .secondary)
                .monospacedDigit()
        }
    }

    private func lookup() {
        guard let normalized = CertificateCode.normalize(code), !isSearching else { return }
        isSearching = true
        lookedUp = normalized
        Task {
            defer { isSearching = false }
            do {
                let found = try await api.certificate(code: normalized)
                withAnimation(.snappy) {
                    certificate = found
                    code = found.code
                    amount = cart.suggestedCertificateAmount(balance: found.balance, code: found.code)
                }
                focusesCode = false
            } catch {
                certificate = nil
                errorMessage = error.userMessage
            }
        }
    }

    private func apply() {
        guard let certificate, canApply else { return }
        cart.addCertificateCharge(certificate, amount: amount)
        dismiss()
    }
}

/// Code, balance, validity and recipient of a looked-up certificate.
struct CertificateSummarySection: View {
    let certificate: GiftCertificate

    var body: some View {
        Section("Сертификат") {
            LabeledContent("Код") { Text(certificate.code).monospaced() }
            LabeledContent("Остаток") {
                Text(Money.format(certificate.balance)).font(.title3.weight(.bold)).monospacedDigit()
            }
            if certificate.balance != certificate.amount {
                LabeledContent("Номинал") { MoneyText(certificate.amount) }
            }
            LabeledContent("Действует", value: CertificateText.validity(certificate.expiresAt))
            LabeledContent("Статус") { CertificateStatusBadge(status: certificate.status) }
            if let recipient = certificate.recipientName.nonEmpty {
                LabeledContent("Кому", value: recipient)
            }
        }
    }
}

struct CertificateStatusBadge: View {
    let status: GiftCertificateStatus

    var body: some View {
        StatusBadge(text: CertificateText.statusTitle(status), color: color)
    }

    private var color: Color {
        switch status {
        case .active: .green
        case .used: .secondary
        case .expired: .orange
        case .cancelled: .red
        case .unknown: .secondary
        }
    }
}

#if DEBUG
#Preview {
    CertificateLookupSheet()
        .previewEnvironment()
}
#endif
