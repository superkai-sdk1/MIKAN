import SwiftUI

/// Texts of a recorded stock count.
nonisolated enum RevisionText {
    /// «Ревизия №3».
    static func title(_ revision: StockRevision) -> String { "Ревизия №\(revision.number)" }

    /// «Расходники», or «Весь склад» for a mixed count.
    static func section(_ revision: StockRevision) -> String { revision.section?.title ?? "Весь склад" }

    /// «−5 шт · 1 200 ₽» — units with their value at cost.
    static func units(_ units: Int, cost: Int, sign: String) -> String {
        units == 0 ? "0" : "\(sign)\(units) · \(Money.format(cost))"
    }
}

/// Totals, availability changes and adjustment movements of a count.
struct RevisionDetailContent: View {
    let revision: StockRevision
    /// `nil` while the movements are loading.
    var movements: [StockMovement]?
    /// Why the movements did not load.
    var movementsFailure: String?
    var onRetry: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(title: "Проверено", value: "\(revision.counted)", systemImage: "checklist")
                StatTile(
                    title: "Расхождений",
                    value: "\(revision.changed)",
                    systemImage: "exclamationmark.triangle",
                    tint: revision.changed == 0 ? .green : .orange
                )
                StatTile(
                    title: "Недостача",
                    value: RevisionText.units(revision.shortage, cost: revision.shortageCost, sign: Money.minus),
                    systemImage: "arrow.down.circle",
                    tint: .red
                )
                StatTile(
                    title: "Излишек",
                    value: RevisionText.units(revision.surplus, cost: revision.surplusCost, sign: "+"),
                    systemImage: "arrow.up.circle",
                    tint: .green
                )
            }
            if revision.changed == 0 {
                Label("Всё сошлось с остатками", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .cardStyle()
            }
            if !revision.presenceChanges.isEmpty {
                presenceCard
            }
            movementsCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusBadge(text: RevisionText.section(revision), color: .accentColor)
                Text(DateText.dateTime(revision.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let employee = revision.employee {
                Label(employee.name, systemImage: "person")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let note = revision.note.nonEmpty {
                Text(note).font(.body)
            }
        }
    }

    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Наличие").font(.headline)
            ForEach(revision.presenceChanges, id: \.productId) { change in
                HStack(spacing: 8) {
                    Text(change.productName)
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    StatusBadge(text: change.from.title, color: change.from.color)
                    Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(.secondary)
                    StatusBadge(text: change.to.title, color: change.to.color)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var movementsCard: some View {
        let hasQuantityChanges = revision.shortage > 0 || revision.surplus > 0
        if hasQuantityChanges {
            VStack(alignment: .leading, spacing: 12) {
                Text("Исправленные остатки").font(.headline)
                if let movements {
                    ForEach(movements) { movement in
                        MovementRow(movement: movement, showsProduct: true)
                        if movement.id != movements.last?.id { Divider() }
                    }
                } else if let movementsFailure {
                    Text(movementsFailure).foregroundStyle(.secondary)
                    if let onRetry {
                        Button("Повторить") { Task { await onRetry() } }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .cardStyle()
        }
    }
}

/// A count from the history: the list item, then the full record with its movements.
struct RevisionDetailView: View {
    @Environment(APIClient.self) private var api
    @State private var revision: StockRevision
    @State private var detail = Remote<StockRevision>()

    init(revision: StockRevision) {
        _revision = State(initialValue: revision)
    }

    var body: some View {
        ScrollView {
            RevisionDetailContent(
                revision: detail.value ?? revision,
                movements: detail.value?.movements,
                movementsFailure: detail.failure,
                onRetry: load
            )
            .padding(16)
        }
        .background { AuraBackground() }
        .navigationTitle(RevisionText.title(revision))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .remoteErrorAlert(detail)
    }

    private func load() async {
        let id = revision.id
        await detail.load { try await api.revision(id: id) }
        if let value = detail.value { revision = value }
    }
}

/// Shown once a count is recorded.
struct RevisionResultView: View {
    let revision: StockRevision
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: revision.id)
                    Text("\(RevisionText.title(revision)) проведена")
                        .font(.title2.weight(.bold))
                    Text(revision.changed == 0
                        ? "Остатки подтверждены."
                        : "Остатки на складе исправлены по факту.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                RevisionDetailContent(revision: revision, movements: revision.movements)
            }
            .padding(16)
        }
        .background { AuraBackground() }
        .navigationTitle("Готово")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово", action: onDone)
            }
        }
        .sensoryFeedback(.success, trigger: revision.id)
    }
}

#if DEBUG
#Preview("Результат") {
    NavigationStack {
        RevisionResultView(revision: PreviewData.revision) {}
    }
    .previewEnvironment()
}
#endif
