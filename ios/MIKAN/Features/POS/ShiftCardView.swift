import SwiftUI

/// Cash shift status at the top of «Касса», with open / deposit / withdraw / close actions.
struct ShiftCardView: View {
    @Environment(ShiftStore.self) private var shift
    @State private var sheet: ShiftSheet?

    enum ShiftSheet: Identifiable {
        case open
        case deposit
        case withdrawal
        /// Captures the shift so the sheet can show the result after `current` becomes `nil`.
        case close(CashShift)

        var id: String {
            switch self {
            case .open: "open"
            case .deposit: "deposit"
            case .withdrawal: "withdrawal"
            case .close(let shift): "close-\(shift.id)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let current = shift.current {
                openContent(current)
            } else if shift.hasLoaded {
                closedContent
            } else if let error = shift.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Повторить") { Task { await shift.refresh() } }
                    .buttonStyle(.glass)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .cardStyle()
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .open: OpenShiftSheet()
            case .deposit: CashOperationSheet(type: .deposit)
            case .withdrawal: CashOperationSheet(type: .withdrawal)
            case .close(let current): CloseShiftSheet(shift: current)
            }
        }
    }

    private var closedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Смена закрыта", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Откройте смену, чтобы вести учёт наличных в кассе. Продавать можно и без смены.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                sheet = .open
            } label: {
                Label("Открыть смену", systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    private func openContent(_ current: CashShift) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Смена открыта", systemImage: "circle.fill")
                    .labelStyle(OpenShiftLabelStyle())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("с \(DateText.time(current.openedAt)) · \(current.openedBy.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("В кассе").font(.subheadline).foregroundStyle(.secondary)
                Text(Money.format(current.expectedCash))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(current.expectedCash)))
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 20) {
                metric("Выручка", Money.format(current.summary.revenue))
                metric("Продажи", "\(current.summary.salesCount)")
                metric("Безнал", Money.format(current.summary.nonCash))
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { sheet = .deposit } label: { ActionLabel(title: "Внести", systemImage: "plus.circle") }
                    Button { sheet = .withdrawal } label: { ActionLabel(title: "Изъять", systemImage: "minus.circle") }
                    Button { sheet = .close(current) } label: { ActionLabel(title: "Закрыть", systemImage: "lock.fill") }
                        .accessibilityLabel("Закрыть смену")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OpenShiftLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 8))
                .foregroundStyle(.green)
            configuration.title
        }
    }
}

#if DEBUG
#Preview {
    ShiftCardView()
        .padding()
        .previewEnvironment()
}
#endif
