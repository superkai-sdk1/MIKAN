import SwiftUI

/// The rows of one product in the counting list: a size row for a product without sizes, a title row plus a row per
/// size otherwise, or the availability control of a «есть / нет» consumable.
struct RevisionProductRows: View {
    let product: RevisionProduct
    @Binding var draft: RevisionDraft
    var focus: FocusState<Int?>.Binding

    private static let thumbnailSize: CGFloat = 40

    var body: some View {
        if product.isPresence {
            presenceRow
        } else if product.hasSeveralSizes || product.sizes.first?.name.nonEmpty != nil {
            titleRow
            ForEach(product.sizes) { size in
                sizeRow(size, title: size.title)
            }
        } else if let size = product.sizes.first {
            sizeRow(size, title: product.name, showsThumbnail: true)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            ProductThumbnail(path: product.photoPath, size: Self.thumbnailSize)
            Text(product.name)
                .font(.headline)
                .lineLimit(2)
            Spacer(minLength: 8)
            if draft.isChecked(product) {
                Button("Сбросить", systemImage: "arrow.uturn.backward") {
                    withAnimation(.snappy) { draft = draft.clearing(productId: product.id) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Сбросить подсчёт «\(product.name)»")
            }
        }
        .listRowSeparator(.hidden, edges: .bottom)
        .accessibilityElement(children: .contain)
    }

    private func sizeRow(_ size: RevisionSize, title: String, showsThumbnail: Bool = false) -> some View {
        RevisionSizeRow(
            title: title,
            unit: product.unit,
            expected: size.expected,
            count: draft.count(for: size),
            isChecked: draft.isChecked(size),
            delta: draft.delta(for: size),
            thumbnailPath: showsThumbnail ? product.photoPath : nil,
            focus: focus,
            focusId: size.id,
            onCount: { draft = draft.settingCount($0, for: size.id) },
            onStep: { step in draft = draft.adjustingCount(for: size.id, by: step) },
            onCheck: {
                withAnimation(.snappy) {
                    draft = draft.isChecked(size) ? draft.settingCount(nil, for: size.id) : draft.confirming(sizeId: size.id)
                }
            }
        )
        .listRowBackground(rowBackground(delta: draft.delta(for: size)))
    }

    private var presenceRow: some View {
        let expected = product.expectedStatus ?? .ok
        let marked = draft.marks[product.id]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProductThumbnail(path: product.photoPath, size: Self.thumbnailSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.headline).lineLimit(2)
                    Text(presenceCaption(expected: expected, marked: marked))
                        .font(.caption)
                        .foregroundStyle(marked.map { $0 == expected ? Color.green : $0.color } ?? .secondary)
                }
                Spacer(minLength: 8)
                if marked != nil {
                    Button("Сбросить", systemImage: "arrow.uturn.backward") {
                        withAnimation(.snappy) { draft = draft.clearing(productId: product.id) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            PresenceStatusPicker(selection: marked, suggested: expected) { status in
                withAnimation(.snappy) { draft = draft.markingStatus(status, for: product.id) }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(marked.map { $0 == expected ? nil : $0.color.opacity(0.1) } ?? nil)
    }

    private func presenceCaption(expected: PresenceStatus, marked: PresenceStatus?) -> String {
        guard let marked else { return "Было: \(expected.title.lowercased()) · не проверено" }
        return marked == expected ? "Сходится: \(marked.title.lowercased())" : "\(expected.title) → \(marked.title.lowercased())"
    }

    private func rowBackground(delta: Int?) -> Color? {
        guard let delta, delta != 0 else { return nil }
        return (delta > 0 ? Color.green : Color.red).opacity(0.1)
    }
}

/// One size: «сходится» tick, the expected stock, ± delta, and the count with big − / + buttons.
private struct RevisionSizeRow: View {
    let title: String
    let unit: String
    let expected: Int
    let count: Int
    let isChecked: Bool
    let delta: Int?
    let thumbnailPath: String?
    var focus: FocusState<Int?>.Binding
    let focusId: Int
    let onCount: (Int?) -> Void
    let onStep: (Int) -> Void
    let onCheck: () -> Void

    private static let control: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            checkButton
            if let thumbnailPath {
                ProductThumbnail(path: thumbnailPath, size: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(thumbnailPath == nil ? .body.weight(.medium) : .headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text("Учтено \(InventoryText.quantity(expected, unit: unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let delta, delta != 0 {
                        DeltaBadge(delta: delta)
                    }
                }
            }
            Spacer(minLength: 4)
            stepper
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var checkButton: some View {
        Button(action: onCheck) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isChecked ? (delta == 0 ? Color.green : Color.accentColor) : Color.secondary.opacity(0.6))
                .frame(width: 32, height: Self.control)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isChecked ? "Проверено" : "Сходится")
        .accessibilityHint(isChecked ? "Снять отметку" : "Отметить: на месте \(InventoryText.quantity(expected, unit: unit))")
        .sensoryFeedback(.selection, trigger: isChecked)
    }

    private var stepper: some View {
        HStack(spacing: 6) {
            stepButton(-1, systemImage: "minus", label: "Меньше")
                .disabled(count <= 0)
            RevisionCountField(value: count, isChecked: isChecked, placeholder: expected, onChange: onCount)
                .focused(focus, equals: focusId)
                .accessibilityLabel("\(title): посчитано")
            stepButton(1, systemImage: "plus", label: "Больше")
        }
    }

    private func stepButton(_ step: Int, systemImage: String, label: String) -> some View {
        Button {
            onStep(step)
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(label)
        .sensoryFeedback(step > 0 ? .increase : .decrease, trigger: count)
    }
}

/// «+2» / «−1» against the expected stock.
struct DeltaBadge: View {
    let delta: Int

    var body: some View {
        Text(delta > 0 ? "+\(delta)" : "\(Money.minus)\(-delta)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(delta > 0 ? Color.green : Color.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background((delta > 0 ? Color.green : Color.red).opacity(0.15), in: .capsule)
            .accessibilityLabel(delta > 0 ? "излишек \(delta)" : "недостача \(-delta)")
    }
}

/// The counted number: digits only, updated on every keystroke; focusing selects it so typing replaces it.
/// Grey until the size is checked; empty input clears the check (the placeholder shows the expected stock).
private struct RevisionCountField: View {
    let value: Int
    let isChecked: Bool
    let placeholder: Int
    let onChange: (Int?) -> Void

    @State private var text: String
    /// The text last written from outside (prefill, steppers, «сходится»): its echo in `onChange(of: text)` is not
    /// the user typing, so it must not check the size.
    @State private var syncedText: String
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(value: Int, isChecked: Bool, placeholder: Int, onChange: @escaping (Int?) -> Void) {
        self.value = value
        self.isChecked = isChecked
        self.placeholder = placeholder
        self.onChange = onChange
        _text = State(initialValue: String(value))
        _syncedText = State(initialValue: String(value))
    }

    var body: some View {
        TextField(String(placeholder), text: $text, selection: $selection)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isChecked ? Color.primary : Color.secondary)
            .frame(width: 58, height: 44)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
            .focused($isFocused)
            .onChange(of: text) { _, newText in
                let parsed = Money.parse(newText)
                let digits = parsed.map(String.init) ?? ""
                guard digits == newText else {
                    text = digits
                    return
                }
                guard newText != syncedText else { return }
                syncedText = newText
                onChange(parsed)
            }
            .onChange(of: value) { sync() }
            .onChange(of: isChecked) { sync() }
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                // After the caret lands: select the number, so the first digit replaces it.
                Task { selection = TextSelection(range: text.startIndex..<text.endIndex) }
            }
    }

    /// Shows an outside change; a field the user emptied stays empty while the size is unchecked.
    private func sync() {
        if text.isEmpty && !isChecked { return }
        if Money.parse(text) == value && (isChecked || text == String(value)) { return }
        syncedText = String(value)
        text = syncedText
    }
}
