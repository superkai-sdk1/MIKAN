import SwiftUI

/// «Мастера»: revenue of the sales linked to each master's appointments, visits, services and no-shows.
struct AnalyticsMastersCard: View {
    let masters: [AnalyticsMaster]

    private var total: Int { masters.reduce(0) { $0 + $1.revenue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalyticsCardTitle(title: "Мастера", systemImage: "person.2", caption: "Чеки, привязанные к записям мастера")
            ForEach(masters) { master in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Circle().fill(Color.master(master.employee.color)).frame(width: 10, height: 10)
                        Text(master.employee.name).font(.subheadline.weight(.medium))
                        Spacer()
                        MoneyText(master.revenue).font(.subheadline.weight(.semibold))
                    }
                    Text(ReportText.masterLine(master) + (master.salesCount > 0 ? " · ср. чек \(Money.format(master.averageCheck))" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: ReportText.share(master.revenue, of: total))
                        .tint(Color.master(master.employee.color))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }
}

/// «Клиенты»: new cards, first-time and returning buyers, receipts without a client and the top clients (opening
/// the client card).
struct AnalyticsClientsCard: View {
    let clients: AnalyticsClients

    private var buyersRevenue: Int { clients.firstTime.revenue + clients.returning.revenue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Клиенты", systemImage: "person.3", caption: "Покупателей: \(clients.buyers)")
            AnalyticsValueRow(title: "Новые карточки", value: "\(clients.newClients)")
            AnalyticsShareRow(
                title: "Впервые", amount: clients.firstTime.revenue,
                share: ReportText.share(clients.firstTime.revenue, of: buyersRevenue),
                detail: "Клиентов: \(clients.firstTime.count)", color: AnalyticsPalette.color(1)
            )
            AnalyticsShareRow(
                title: "Повторно", amount: clients.returning.revenue,
                share: ReportText.share(clients.returning.revenue, of: buyersRevenue),
                detail: "Клиентов: \(clients.returning.count)", color: AnalyticsPalette.color(0)
            )
            if clients.anonymous.salesCount > 0 {
                AnalyticsMoneyRow(title: "Чеки без клиента", amount: clients.anonymous.revenue, detail: "Чеков: \(clients.anonymous.salesCount)")
            }
            AnalyticsHint(text: "Повторные — покупали или были на процедуре раньше этого периода.")
            if !clients.top.isEmpty {
                Divider()
                Text("Топ клиентов").font(.subheadline.weight(.semibold))
                AnalyticsTopList(items: clients.top) { index, top in
                    NavigationLink {
                        ClientDetailView(clientId: top.client.id)
                    } label: {
                        RankedRow(index: index, title: top.client.fullName, detail: "Чеков: \(top.salesCount) · визитов: \(top.visits)", amount: top.revenue)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }
}

/// «Записи»: outcomes of the appointments that started in the period and the revenue lost to no-shows.
struct AnalyticsAppointmentsCard: View {
    let appointments: AnalyticsAppointments

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsCardTitle(title: "Записи", systemImage: "calendar", caption: "Всего: \(appointments.total)")
            AnalyticsValueRow(title: "Завершены", value: "\(appointments.completed)")
            if appointments.open > 0 {
                AnalyticsValueRow(title: "Ещё впереди", value: "\(appointments.open)")
            }
            AnalyticsValueRow(title: "Отменены", value: "\(appointments.cancelled)",
                              detail: appointments.cancelledValue > 0 ? "На сумму \(Money.format(appointments.cancelledValue))" : nil)
            AnalyticsValueRow(title: "Неявки", value: "\(appointments.noShow)", detail: "Доля неявок: \(ReportText.noShowRate(appointments))",
                              tint: appointments.noShow > 0 ? .red : nil)
            Divider()
            AnalyticsMoneyRow(title: "Потеряно из-за неявок", amount: appointments.noShowLoss, isEmphasized: true,
                              tint: appointments.noShowLoss > 0 ? .red : nil)
            AnalyticsHint(text: "Удержанные после неявок предоплаты — в карточке «Предоплаты».")
        }
        .cardStyle()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                AnalyticsMastersCard(masters: PreviewData.analytics.masters)
                AnalyticsClientsCard(clients: PreviewData.analytics.clients)
                AnalyticsAppointmentsCard(appointments: PreviewData.analytics.appointments)
            }
            .padding()
        }
        .background { AuraBackground() }
    }
    .previewEnvironment()
}
#endif
