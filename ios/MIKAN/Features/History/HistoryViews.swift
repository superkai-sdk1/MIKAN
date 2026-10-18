import SwiftUI

/// One history line: what was done or sold, when, by whom and for how much.
struct HistoryEntryRow: View {
    let entry: HistoryEntry
    /// Service / product history shows who the client was; the client card does not.
    var showsClient = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind == .service ? "sparkles" : "bag.fill")
                .font(.subheadline)
                .foregroundStyle(entry.kind == .service ? Color.accentColor : .blue)
                .frame(width: 30, height: 30)
                .background(.fill.tertiary, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .strikethrough(entry.refunded)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(Money.format(entry.total))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .strikethrough(entry.refunded)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if entry.refunded {
                    StatusBadge(text: "Возврат", color: .red, systemImage: "arrow.uturn.backward")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// «Лабрет — 8 мм × 2»: the server names product entries with their size; an entry whose name lacks it
    /// still gets it from `variantName`.
    private var itemName: String {
        let name = SizeLabel.fullName(name: entry.name, size: entry.variantName)
        return entry.quantity > 1 ? "\(name) × \(entry.quantity)" : name
    }

    private var title: String {
        guard showsClient else { return itemName }
        return entry.client?.fullName ?? "Без клиента"
    }

    private var subtitle: String {
        var parts = [DateText.fullDate(entry.date)]
        if showsClient { parts.insert(itemName, at: 0) }
        if let employee = entry.employee { parts.append(employee.name) }
        if let number = entry.saleNumber { parts.append("чек №\(number)") }
        return parts.joined(separator: " · ")
    }
}

/// History row that opens the appointment (services) or the receipt (products) behind it.
struct HistoryEntryLink: View {
    let entry: HistoryEntry
    var showsClient = false

    var body: some View {
        if entry.appointmentId != nil || entry.saleId != nil {
            NavigationLink {
                HistoryEntryDestination(entry: entry)
            } label: {
                HistoryEntryRow(entry: entry, showsClient: showsClient)
            }
        } else {
            HistoryEntryRow(entry: entry, showsClient: showsClient)
        }
    }
}

/// Loads the appointment or sale of a history entry and shows its detail screen.
struct HistoryEntryDestination: View {
    @Environment(APIClient.self) private var api
    let entry: HistoryEntry

    @State private var target = Remote<Target>()

    enum Target {
        case appointment(Appointment)
        case sale(Sale)
    }

    var body: some View {
        Group {
            switch target.value {
            case .appointment(let appointment):
                AppointmentDetailView(appointment: appointment)
            case .sale(let sale):
                SaleDetailView(sale: sale)
            case nil:
                Color.clear
                    .overlay { RemoteStateOverlay(remote: target, retry: load) }
            }
        }
        .task { if target.value == nil { await load() } }
    }

    /// Products open their receipt; services open the appointment they were done in (else the receipt).
    private func load() async {
        await target.load {
            if entry.kind == .product, let id = entry.saleId {
                return .sale(try await api.sale(id: id))
            }
            if let id = entry.appointmentId {
                return .appointment(try await api.appointment(id: id))
            }
            guard let id = entry.saleId else { throw APIError.transport(message: "Нечего открыть.") }
            return .sale(try await api.sale(id: id))
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        List(PreviewData.historyEntries) { entry in
            HistoryEntryLink(entry: entry)
        }
    }
    .previewEnvironment()
}
#endif
