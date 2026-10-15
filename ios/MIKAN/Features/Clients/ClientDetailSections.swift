import SwiftUI

struct ClientHeaderSection: View {
    let client: Client

    var body: some View {
        Section {
            VStack(spacing: 10) {
                InitialsAvatar(name: client.name, size: 84)
                Text(client.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if let phone = client.phone.nonEmpty {
                    Text(PhoneText.display(phone))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    if client.telegramLinked {
                        StatusBadge(text: "Telegram", color: .blue, systemImage: "paperplane.fill")
                    }
                    if client.archived {
                        StatusBadge(text: "В архиве", color: .gray, systemImage: "archivebox")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }
}

struct ClientStatsSection: View {
    let stats: ClientStats?

    var body: some View {
        Section {
            HStack(spacing: 10) {
                StatTile(title: "Визиты", value: stats.map { "\($0.visits)" } ?? "—")
                StatTile(title: "Потрачено", value: stats.map { Money.format($0.totalSpent) } ?? "—")
                StatTile(title: "Последний", value: lastVisit)
            }
            if let upcoming = stats?.upcomingAppointments, upcoming > 0 {
                Label("Предстоящих записей: \(upcoming)", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var lastVisit: String {
        guard let date = stats?.lastVisitAt else { return "—" }
        return DateText.dayMonth(date)
    }
}
