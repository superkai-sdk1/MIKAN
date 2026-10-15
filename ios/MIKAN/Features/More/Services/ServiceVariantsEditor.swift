import SwiftUI

/// Variants of the service editor: a section per variant, then the «add» section with the explanation.
struct ServiceVariantsEditor: View {
    @Binding var variants: [ServiceVariantDraft]
    let serviceName: String
    /// Price and duration a new variant starts from.
    let defaultPrice: Int
    let defaultDuration: Int

    @FocusState private var focusedVariant: UUID?

    var body: some View {
        ForEach($variants) { $variant in
            Section {
                TextField("Название, например «Два»", text: $variant.name)
                    .focused($focusedVariant, equals: variant.id)
                NumberField.money("Цена", value: $variant.price)
                Toggle("Своя длительность", isOn: $variant.hasDuration)
                if variant.hasDuration {
                    ServiceDurationStepper(title: "Длительность", minutes: $variant.durationMin)
                }
            } header: {
                header(for: variant.id)
            }
        }
        Section {
            Button("Добавить вариант", systemImage: "plus.circle.fill", action: add)
                .disabled(variants.count >= ServiceLimits.maxVariants)
        } header: {
            if variants.isEmpty {
                Text("Варианты")
            }
        } footer: {
            if let message = ServiceVariantDrafts.validationMessage(for: variants) {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Например, «Один» и «Два». При записи выбирают один вариант — в записи будет «\(exampleLine)» с ценой и длительностью варианта.")
            }
        }
    }

    private func header(for id: UUID) -> some View {
        let index = variants.firstIndex { $0.id == id } ?? 0
        return HStack {
            Text("Вариант \(index + 1)")
            Spacer()
            Menu {
                Button("Выше", systemImage: "arrow.up") {
                    variants = ServiceVariantDrafts.moving(id, by: -1, in: variants)
                }
                .disabled(index == 0)
                Button("Ниже", systemImage: "arrow.down") {
                    variants = ServiceVariantDrafts.moving(id, by: 1, in: variants)
                }
                .disabled(index >= variants.count - 1)
                Divider()
                Button("Удалить вариант", systemImage: "trash", role: .destructive) {
                    variants = ServiceVariantDrafts.removing(id, from: variants)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .accessibilityLabel("Действия с вариантом \(index + 1)")
            }
        }
    }

    /// «Соски — Два» from the current input, with a sample when it is still empty.
    private var exampleLine: String {
        let name = serviceName.nonEmpty ?? "Соски"
        let variant = variants.lazy.compactMap { $0.name.nonEmpty }.first ?? "Два"
        return "\(name) — \(variant)"
    }

    private func add() {
        let draft = ServiceVariantDraft.new(price: defaultPrice, defaultDuration: defaultDuration)
        variants = variants + [draft]
        // The new row's text field exists only after this update, so focus it on the next turn.
        Task { focusedVariant = draft.id }
    }
}
