import SwiftUI

/// Completes an appointment: aftercare message, consumables used (prefilled from the services' norms),
/// then shows what was taken from the warehouse and offers to take payment.
struct CompleteAppointmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference

    let appointment: Appointment
    let onCompleted: (Appointment) -> Void
    let onPay: (Appointment) -> Void

    @State private var sendsAftercare: Bool
    @State private var templateId: Int?
    @State private var consumables = Remote<[Product]>()
    /// The visit's norms; prefilled once the services and the consumables are loaded.
    @State private var norms: [ServiceConsumable] = []
    @State private var presence: [Product] = []
    @State private var usage: [Int: Int] = [:]
    @State private var shownConsumables: [Int] = []
    @State private var didPrefill = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var result: CompleteAppointmentResult?

    init(
        appointment: Appointment,
        onCompleted: @escaping (Appointment) -> Void,
        onPay: @escaping (Appointment) -> Void
    ) {
        self.appointment = appointment
        self.onCompleted = onCompleted
        self.onPay = onPay
        _sendsAftercare = State(initialValue: appointment.client.telegramLinked)
    }

    private var isTelegramLinked: Bool { appointment.client.telegramLinked }
    /// Some service of the visit is a fresh piercing / tattoo: only then the server sends a memo.
    private var hasFreshProcedure: Bool { AftercareDefaults.sendsMemo(for: appointment, services: reference.services) }
    private var canSendAftercare: Bool { isTelegramLinked && hasFreshProcedure }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    CompletionSuccessView(
                        appointment: result.appointment,
                        scheduledMessages: result.scheduledMessages,
                        consumption: result.consumption,
                        units: units
                    ) {
                        onPay(result.appointment)
                        dismiss()
                    } onDone: {
                        dismiss()
                    }
                } else {
                    form
                }
            }
            .navigationTitle(result == nil ? "Завершить запись" : "Готово")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Button("Завершить") { submit() }
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .errorAlert($errorMessage)
            .sensoryFeedback(.success, trigger: result != nil)
            .task { await load() }
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Отправить памятку по уходу", isOn: $sendsAftercare)
                    .disabled(!canSendAftercare)
                if sendsAftercare && canSendAftercare {
                    Picker("Шаблон", selection: $templateId) {
                        Text("Не выбран").tag(Int?.none)
                        ForEach(reference.templates) { template in
                            Text(template.name).tag(Int?.some(template.id))
                        }
                    }
                }
            } header: {
                Text("Уход")
            } footer: {
                if !isTelegramLinked {
                    Text("У клиента не подключён Telegram — памятку отправить нельзя. Подключите бота в карточке клиента.")
                } else if !hasFreshProcedure {
                    Text(AftercareDefaults.noFreshProcedureHint)
                } else if sendsAftercare && templateId == nil {
                    Text("Выберите шаблон, иначе памятка не будет отправлена.").foregroundStyle(.orange)
                } else {
                    Text("Первое сообщение придёт через несколько минут, остальные — по расписанию шаблона.")
                }
            }
            consumablesSection
        }
    }

    private var consumablesSection: some View {
        CompleteConsumablesSection(
            products: consumables,
            norms: norms,
            presence: presence,
            usage: $usage,
            shown: $shownConsumables,
            retry: loadConsumables
        )
    }

    private var units: [Int: String] {
        Dictionary((consumables.value ?? []).map { ($0.id, $0.unitLabel) }, uniquingKeysWith: { first, _ in first })
    }

    private func load() async {
        async let consumablesLoad: Void = loadConsumables()
        do {
            try await reference.ensureTemplates()
            try await reference.ensureServices()
            if templateId == nil {
                templateId = defaultTemplateId()
            }
            if !hasFreshProcedure {
                sendsAftercare = false
            }
        } catch {
            errorMessage = error.userMessage
        }
        await consumablesLoad
        prefillIfNeeded()
    }

    /// Inactive ones too, so every norm of the visit's services resolves.
    private func loadConsumables() async {
        await consumables.load { try await api.products(kind: .consumable, includeInactive: true) }
        prefillIfNeeded()
    }

    /// Fills the steppers from the norms once, when both the services and the consumables are there.
    /// Anything staff already added keeps its count.
    private func prefillIfNeeded() {
        guard !didPrefill, let products = consumables.value, !reference.services.isEmpty else { return }
        didPrefill = true
        norms = VisitConsumption.norms(for: appointment, services: reference.services, products: products)
        presence = VisitConsumption.presenceProducts(for: appointment, services: reference.services, products: products)
        usage = VisitConsumption.usage(from: norms).merging(usage) { _, typed in typed }
        let normIds = norms.map(\.productId)
        shownConsumables = normIds + shownConsumables.filter { !normIds.contains($0) }
    }

    private func defaultTemplateId() -> Int? {
        AftercareDefaults.templateId(for: appointment, services: reference.services, templates: reference.templates)
    }

    private func submit() {
        let body = CompleteBody(
            sendAftercare: sendsAftercare && canSendAftercare,
            aftercareTemplateId: sendsAftercare ? templateId : nil,
            // Untouched norms: no list, the server deducts them without blocking and reports shortages.
            consumables: VisitConsumption.consumables(usage: usage, norms: norms)
        )
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let completed = try await api.completeAppointment(id: appointment.id, body)
                onCompleted(completed.appointment)
                withAnimation(.smooth) { result = completed }
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

/// Aftercare memo of an appointment, mirroring the server: memos go out only for services marked «Свежий прокол» /
/// «Свежее тату» (`Service.freshProcedure`).
nonisolated enum AftercareDefaults {
    static let noFreshProcedureHint =
        "В записи нет услуги со «Свежим проколом» или «Свежим тату» — памятка по уходу не отправляется. " +
        "Переключатель — в карточке услуги."

    /// A catalog service of the visit: its template and category, when it may send a memo.
    private struct Candidate {
        let templateId: Int?
        let category: ServiceCategory?
    }

    /// The visit's catalog services in line order (the legacy single service when it has no lines) that may send a memo:
    /// fresh ones, plus ones missing from `services` (not loaded yet — the server decides for those).
    private static func candidates(for appointment: Appointment, services: [Service]) -> [Candidate] {
        let refs: [(id: Int, category: ServiceCategory?)] = appointment.services.isEmpty
            ? [appointment.service].compactMap { $0.map { ($0.id, $0.category) } }
            : appointment.services.compactMap { line in line.serviceId.map { ($0, line.category) } }
        return refs.compactMap { ref in
            guard let service = services.first(where: { $0.id == ref.id }) else {
                return Candidate(templateId: nil, category: ref.category)
            }
            return service.freshProcedure ? Candidate(templateId: service.aftercareTemplateId, category: service.category) : nil
        }
    }

    /// Completing the appointment can send a memo: one of its services is a fresh procedure.
    static func sendsMemo(for appointment: Appointment, services: [Service]) -> Bool {
        !candidates(for: appointment, services: services).isEmpty
    }

    /// The template of the first fresh service that has one; else the first template of that service's category.
    static func templateId(
        for appointment: Appointment,
        services: [Service],
        templates: [AftercareTemplate]
    ) -> Int? {
        let fresh = candidates(for: appointment, services: services)
        for candidate in fresh {
            if let templateId = candidate.templateId, templates.contains(where: { $0.id == templateId }) {
                return templateId
            }
        }
        guard let category = fresh.lazy.compactMap(\.category).first else { return nil }
        return templates.first { $0.category == category }?.id
    }
}

#if DEBUG
#Preview {
    CompleteAppointmentSheet(appointment: PreviewData.appointments[0]) { _ in } onPay: { _ in }
        .previewEnvironment()
}
#endif
