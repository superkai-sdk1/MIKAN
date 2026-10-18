import SwiftUI

/// Screens of the stock count sheet.
enum RevisionStep: Hashable {
    case count(CatalogSection)
    case result(StockRevision)
    case history
}

/// «Ревизия»: choose a section → count it → the result. Started from the warehouse toolbar.
struct RevisionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    /// The section the warehouse shows; offered first.
    let initialSection: CatalogSection?
    /// A count was recorded: stocks changed.
    let onFinished: (StockRevision) -> Void

    @State private var path: [RevisionStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            RevisionStartView(current: initialSection) { section in
                path.append(.count(section))
            }
            .navigationDestination(for: RevisionStep.self) { step in
                switch step {
                case .count(let section):
                    RevisionCountView(section: section) { revision in
                        onFinished(revision)
                        // The recorded count cannot be posted again: «назад» from the result leads to the start.
                        path = [.result(revision)]
                    } onCancel: {
                        path.removeAll()
                    }
                case .result(let revision):
                    RevisionResultView(revision: revision) { dismiss() }
                case .history:
                    RevisionHistoryView()
                }
            }
        }
    }
}

/// The sections that can be counted.
private struct RevisionStartView: View {
    @Environment(\.dismiss) private var dismiss
    let current: CatalogSection?
    let onStart: (CatalogSection) -> Void

    private static let sections: [CatalogSection] = [.jewelry, .consumable, .goods]

    var body: some View {
        List {
            Section {
                ForEach(Self.sections) { section in
                    Button {
                        onStart(section)
                    } label: {
                        RevisionSectionRow(section: section, isCurrent: section == current)
                    }
                    .tint(.primary)
                }
            } header: {
                Text("Что пересчитываем")
            } footer: {
                Text("Остатки подставятся сами — исправьте то, что не сходится, и отметьте остальное. Можно пересчитать часть, например одну полку: в ревизию попадёт только проверенное.")
            }
            Section {
                NavigationLink(value: RevisionStep.history) {
                    Label("История ревизий", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .auraBackground()
        .navigationTitle("Ревизия")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть", systemImage: "xmark") { dismiss() }
            }
        }
    }
}

private struct RevisionSectionRow: View {
    let section: CatalogSection
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(section.title).font(.headline)
                    if isCurrent {
                        StatusBadge(text: "открыт на складе", color: .secondary)
                    }
                }
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        switch section {
        case .jewelry: "Каждый размер поштучно"
        case .consumable: "Количество и «есть / нет»"
        case .goods: "Размеры и объёмы поштучно"
        case .service: ""
        }
    }
}

#if DEBUG
#Preview {
    RevisionFlowView(initialSection: .consumable) { _ in }
        .previewEnvironment()
}
#endif
