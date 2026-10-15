import SwiftUI

struct AftercareTemplateEditorView: View {
    enum Change {
        case saved(AftercareTemplate)
        case deleted(Int)
    }

    private struct EditableStep: Identifiable, Hashable {
        let id = UUID()
        var dayOffset: Int
        var text: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(APIClient.self) private var api
    let template: AftercareTemplate?
    let onChange: (Change) -> Void

    @State private var name: String
    @State private var category: ServiceCategory
    @State private var steps: [EditableStep]
    @State private var editMode: EditMode = .inactive
    @State private var confirmsDelete = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let maxDayOffset = 365

    init(template: AftercareTemplate?, onChange: @escaping (Change) -> Void) {
        self.template = template
        self.onChange = onChange
        _name = State(initialValue: template?.name ?? "")
        _category = State(initialValue: template?.category ?? .tattoo)
        let initialSteps = template?.steps.map { EditableStep(dayOffset: $0.dayOffset, text: $0.text) }
            ?? [EditableStep(dayOffset: 0, text: "")]
        _steps = State(initialValue: initialSteps)
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty && !steps.isEmpty && steps.allSatisfy { !$0.text.trimmed.isEmpty } && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                    Picker("Категория", selection: $category) {
                        ForEach(ServiceCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                }
                stepsSection
                if template != nil {
                    Section {
                        Button("Удалить шаблон", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    } footer: {
                        Text("Услуги с этим шаблоном останутся без памятки.")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(template == nil ? "Новый шаблон" : "Шаблон ухода")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Сохранить", action: save).disabled(!canSave) }
                }
            }
            .confirmationDialog("Удалить шаблон «\(name)»?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
                Button("Отмена", role: .cancel) {}
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach($steps) { $step in
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: $step.dayOffset, in: 0...Self.maxDayOffset) {
                        Text(dayTitle(step.dayOffset))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    TextField("Текст сообщения", text: $step.text, axis: .vertical)
                        .lineLimit(2...10)
                }
                .padding(.vertical, 4)
            }
            .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { steps.remove(atOffsets: $0) }
            Button("Добавить сообщение", systemImage: "plus.circle.fill") {
                let nextDay = (steps.map(\.dayOffset).max() ?? -1) + 1
                withAnimation { steps.append(EditableStep(dayOffset: nextDay, text: "")) }
            }
        } header: {
            HStack {
                Text("Сообщения")
                Spacer()
                Button(editMode.isEditing ? "Готово" : "Порядок") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .font(.subheadline)
                .textCase(nil)
            }
        } footer: {
            Text("«Сразу» — отправляется через несколько минут после завершения процедуры. Остальные — в указанный день в час из настроек бота.")
        }
    }

    private func dayTitle(_ offset: Int) -> String {
        offset == 0 ? "Сразу после процедуры" : "Через \(Plural.days(offset))"
    }

    private func save() {
        let body = AftercareTemplateBody(
            name: name.trimmed,
            category: category,
            steps: steps.map { AftercareStep(dayOffset: $0.dayOffset, text: $0.text.trimmed) }
        )
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = if let template {
                    try await api.updateAftercareTemplate(id: template.id, body)
                } else {
                    try await api.createAftercareTemplate(body)
                }
                onChange(.saved(saved))
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }

    private func delete() {
        guard let template else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await api.deleteAftercareTemplate(id: template.id)
                onChange(.deleted(template.id))
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    AftercareTemplateEditorView(template: PreviewData.template) { _ in }
        .previewEnvironment()
}
#endif
