import SwiftUI

/// Sticky glass panel under the counting list: progress, differences in units and at cost, and «Провести ревизию».
struct RevisionSummaryBar: View {
    let draft: RevisionDraft
    let isSaving: Bool
    let onConfirmRest: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Проверено \(draft.checkedCount) из \(draft.lineCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(draft.checkedCount)))
                Spacer()
                if draft.uncheckedCount > 0 {
                    Button("Остальное сходится", action: onConfirmRest)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                        .disabled(isSaving)
                }
            }
            ProgressView(value: draft.progress)
                .tint(draft.uncheckedCount == 0 ? .green : .accentColor)
                .accessibilityHidden(true)
            if draft.changedCount > 0 {
                InventoryFlowLayout(spacing: 6, lineSpacing: 6) {
                    chip("Расхождений: \(draft.changedCount)", color: .orange)
                    if draft.shortage > 0 {
                        chip("Недостача \(Money.minus)\(draft.shortage) · \(Money.format(draft.shortageCost))", color: .red)
                    }
                    if draft.surplus > 0 {
                        chip("Излишек +\(draft.surplus) · \(Money.format(draft.surplusCost))", color: .green)
                    }
                }
            } else if draft.checkedCount > 0 {
                Label("Пока всё сходится", systemImage: "checkmark.seal")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
            }
            Button(action: onSubmit) {
                Group {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Провести ревизию")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!draft.canSubmit || isSaving)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .animation(.snappy, value: draft.changedCount)
        .accessibilityElement(children: .contain)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: .capsule)
    }
}
