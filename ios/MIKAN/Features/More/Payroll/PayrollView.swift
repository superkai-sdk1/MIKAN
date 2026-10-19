import SwiftUI

/// «Зарплата» (Ещё): the owner sees everyone's statements for the period; anyone else goes straight to their own.
struct PayrollView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let employee = appState.employee {
            if employee.role == .owner {
                PayrollListView()
            } else {
                PayrollStatementView(employee: employee.ref, selection: PayrollPeriodSelection())
            }
        } else {
            ContentUnavailableView("Нет данных о сотруднике", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

/// The owner's list: one card per employee with rules or activity in the period, and the period totals.
private struct PayrollListView: View {
    @Environment(APIClient.self) private var api
    @State private var selection = PayrollPeriodSelection()
    @State private var list = Remote<PayrollList>()

    private var range: PayrollRange { selection.range() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PayrollPeriodHeader(selection: $selection)
                if let value = list.value {
                    content(value.items)
                } else if let failure = list.failure {
                    ErrorStateView(message: failure, retry: load)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(16)
        }
        .background { AuraBackground() }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await load() }
        .task(id: range) {
            list.reset()
            await load()
        }
        .remoteErrorAlert(list)
        .navigationTitle("Зарплата")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ items: [PayrollStatement]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                "Начислений нет",
                systemImage: "banknote",
                description: Text("Настройте правила зарплаты в карточке сотрудника: Ещё → Сотрудники.")
            )
        } else {
            totals(items)
            ForEach(items) { statement in
                NavigationLink {
                    PayrollStatementView(employee: statement.employee, selection: selection)
                } label: {
                    PayrollEmployeeRow(statement: statement)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func totals(_ items: [PayrollStatement]) -> some View {
        let due = items.reduce(0) { $0 + max(0, $1.due) }
        return HStack(spacing: 12) {
            StatTile(title: "Начислено", value: Money.format(items.reduce(0) { $0 + $1.earned }), systemImage: "sum")
            StatTile(title: "Выплачено", value: Money.format(items.reduce(0) { $0 + $1.paid }), systemImage: "banknote")
            StatTile(title: "К выплате", value: Money.format(due), systemImage: "hourglass", tint: .orange)
        }
    }

    private func load() async {
        let range = range
        await list.load { try await api.payroll(from: range.from, to: range.to) }
    }
}

/// One employee in the owner's list: what was earned, paid and is still due.
private struct PayrollEmployeeRow: View {
    let statement: PayrollStatement

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: statement.employee.name, color: .master(statement.employee.color), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(statement.employee.name).font(.headline)
                Text("Начислено \(Money.format(statement.earned)) · выплачено \(Money.format(statement.paid))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(PayrollText.dueTitle(statement.due)).font(.caption).foregroundStyle(.secondary)
                MoneyText(abs(statement.due))
                    .font(.headline)
                    .foregroundStyle(statement.due < 0 ? Color.orange : Color.primary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .cardStyle(padding: 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PayrollView()
    }
    .previewEnvironment()
}
#endif
