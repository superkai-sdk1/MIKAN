import SwiftUI

/// A category picked from the section's categories (in staff order), «Без категории», or a new name typed in place
/// (the server creates the category when the item is saved).
struct CategoryField: View {
    var title = "Категория"
    /// Category names in staff order.
    let options: [String]
    /// "" — no category.
    @Binding var selection: String

    @State private var showsNewName = false
    @State private var newName = ""

    var body: some View {
        Menu {
            Button {
                selection = ""
            } label: {
                choiceLabel("Без категории", isSelected: selection.trimmed.isEmpty)
            }
            ForEach(options, id: \.self) { name in
                Button {
                    selection = name
                } label: {
                    choiceLabel(name, isSelected: name == selection)
                }
            }
            Divider()
            Button("Новая категория…", systemImage: "plus") {
                newName = ""
                showsNewName = true
            }
        } label: {
            LabeledContent(title) {
                Text(selection.nonEmpty ?? "Без категории")
                    .foregroundStyle(selection.nonEmpty == nil ? .secondary : .primary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .alert("Новая категория", isPresented: $showsNewName) {
            TextField("Название", text: $newName)
            Button("Добавить") {
                if let name = newName.nonEmpty { selection = name }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Категория появится, когда вы сохраните карточку.")
        }
    }

    @ViewBuilder
    private func choiceLabel(_ text: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }
}
