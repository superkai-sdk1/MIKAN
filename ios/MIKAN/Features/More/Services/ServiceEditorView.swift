import SwiftUI

struct ServiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference

    let service: Service?
    let onSaved: (Service) -> Void

    @State private var name: String
    @State private var category: ServiceCategory
    @State private var price: Int
    @State private var priceFrom: Bool
    @State private var durationMin: Int
    @State private var description: String
    @State private var aftercareTemplateId: Int?
    @State private var active: Bool
    @State private var sort: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let durationStep = 15
    private static let maxDuration = 12 * 60

    init(service: Service?, nextSort: Int, onSaved: @escaping (Service) -> Void) {
        self.service = service
        self.onSaved = onSaved
        _name = State(initialValue: service?.name ?? "")
        _category = State(initialValue: service?.category ?? .piercing)
        _price = State(initialValue: service?.price ?? 0)
        _priceFrom = State(initialValue: service?.priceFrom ?? false)
        _durationMin = State(initialValue: service?.durationMin ?? 60)
        _description = State(initialValue: service?.description ?? "")
        _aftercareTemplateId = State(initialValue: service?.aftercareTemplateId)
        _active = State(initialValue: service?.active ?? true)
        _sort = State(initialValue: service?.sort ?? max(0, nextSort))
    }

    private var canSave: Bool { !name.trimmed.isEmpty && durationMin > 0 && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                    Picker("Категория", selection: $category) {
                        ForEach(ServiceCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                }
                Section {
                    NumberField.money("Цена", value: $price)
                    Toggle("Цена «от»", isOn: $priceFrom)
                    Stepper(value: $durationMin, in: Self.durationStep...Self.maxDuration, step: Self.durationStep) {
                        LabeledContent("Длительность", value: DateText.duration(minutes: durationMin))
                    }
                } footer: {
                    Text("«От» — итоговая цена указывается в каждой записи.")
                }
                Section {
                    TextField("Что входит, подготовка, противопоказания", text: $description, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Описание")
                } footer: {
                    Text("Этот текст видит бот, когда рассказывает клиентам об услуге.")
                }
                Section {
                    Picker("Шаблон ухода", selection: $aftercareTemplateId) {
                        Text("Без памятки").tag(Int?.none)
                        ForEach(reference.templates) { template in
                            Text(template.name).tag(Int?.some(template.id))
                        }
                    }
                } footer: {
                    Text("Памятка по умолчанию при завершении записи с этой услугой.")
                }
                Section {
                    Toggle("Активна", isOn: $active)
                    Stepper(value: $sort, in: 0...999) {
                        LabeledContent("Порядок в списке", value: "\(sort)")
                    }
                } footer: {
                    Text("Скрытые услуги не показываются при записи, в кассе и боту.")
                }
            }
            .navigationTitle(service == nil ? "Новая услуга" : "Услуга")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Сохранить", action: save).disabled(!canSave) }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task {
                do { try await reference.ensureTemplates() } catch { errorMessage = error.userMessage }
            }
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        let body = ServiceBody(
            name: name.trimmed,
            category: category,
            price: price,
            priceFrom: priceFrom,
            durationMin: durationMin,
            description: Nullable(description.nonEmpty),
            aftercareTemplateId: Nullable(aftercareTemplateId),
            active: active,
            sort: sort
        )
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = if let service {
                    try await api.updateService(id: service.id, body)
                } else {
                    try await api.createService(body)
                }
                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    ServiceEditorView(service: PreviewData.lobe, nextSort: 2) { _ in }
        .previewEnvironment()
}
#endif
