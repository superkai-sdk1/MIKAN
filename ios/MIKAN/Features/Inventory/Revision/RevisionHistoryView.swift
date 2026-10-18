import SwiftUI

/// «История ревизий»: recorded stock counts, newest first, loaded page by page.
struct RevisionHistoryView: View {
    @Environment(APIClient.self) private var api
    @State private var revisions = Remote<[StockRevision]>()
    @State private var total = 0
    @State private var isLoadingMore = false

    private static let pageSize = 50

    var body: some View {
        List {
            ForEach(revisions.value ?? []) { revision in
                NavigationLink {
                    RevisionDetailView(revision: revision)
                } label: {
                    RevisionRow(revision: revision)
                }
                .task { await loadMore(after: revision) }
            }
            if isLoadingMore {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .auraBackground()
        .overlay {
            RemoteStateOverlay(remote: revisions, retry: load) {
                ContentUnavailableView(
                    "Ревизий пока не было",
                    systemImage: "checklist",
                    description: Text("Проведите ревизию из меню склада — здесь появится, что сошлось и что исправили.")
                )
            }
        }
        .refreshable { await load() }
        .task {
            // Coming back from a pushed revision keeps the loaded pages.
            guard revisions.value == nil else { return }
            await load()
        }
        .remoteErrorAlert(revisions)
        .navigationTitle("История ревизий")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        await revisions.load {
            let page = try await api.revisions(limit: Self.pageSize)
            total = page.total ?? page.items.count
            return page.items
        }
    }

    private func loadMore(after revision: StockRevision) async {
        guard let items = revisions.value, revision.id == items.last?.id, items.count < total, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.revisions(limit: Self.pageSize, offset: items.count)
            let known = Set(items.map(\.id))
            revisions.update { $0 + page.items.filter { !known.contains($0.id) } }
        } catch is CancellationError {
            return
        } catch {
            revisions.transientError = error.userMessage
        }
    }
}

/// «Ревизия №3 · Расходники», when and who, and how it went.
private struct RevisionRow: View {
    let revision: StockRevision

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: revision.changed == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(revision.changed == 0 ? Color.green : Color.orange)
                .frame(width: 28, height: 28)
                .background((revision.changed == 0 ? Color.green : Color.orange).opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(RevisionText.title(revision)) · \(RevisionText.section(revision))")
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = revision.note.nonEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(revision.changed == 0 ? "Сошлось" : "Расхождений: \(revision.changed)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(revision.changed == 0 ? Color.green : Color.primary)
                if revision.shortageCost > 0 {
                    Text("\(Money.minus)\(Money.format(revision.shortageCost))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [DateText.dateTime(revision.createdAt), "проверено \(revision.counted)"]
        if let employee = revision.employee { parts.append(employee.name) }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        RevisionHistoryView()
    }
    .previewEnvironment()
}
#endif
