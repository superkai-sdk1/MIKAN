import SwiftUI

/// «Касса» hub: shift card, the open receipt / «Открыть чек без записи», today's appointments awaiting payment.
/// Receipts are pushed onto `AppState.posPath`, so the schedule and the client card can land on them too.
struct POSView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    @Environment(ShiftStore.self) private var shift

    @State private var queue = Remote<[Appointment]>()
    @State private var catalog = Remote<[Product]>()
    @State private var confirmsNewReceipt = false
    @State private var replacingFor: Appointment?

    var body: some View {
        @Bindable var appState = appState
        @Bindable var cart = cart
        NavigationStack(path: $appState.posPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ShiftCardView()
                    ReceiptEntryCard(onContinue: continueReceipt, onNew: requestNewReceipt)
                    PaymentQueueSection(
                        queue: queue,
                        openAppointmentId: cart.appointmentId,
                        retry: loadQueue,
                        onSelect: select
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background { AuraBackground() }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable {
                await loadQueue()
                await shift.refresh()
            }
            // Runs on every appearance (also when popping back from a receipt) and after each sale.
            .task(id: cart.salesCompleted) {
                await loadQueue()
                if !shift.hasLoaded { await shift.refresh() }
            }
            .remoteErrorAlert(queue)
            .navigationTitle("Касса")
            .toolbar { toolbarContent }
            .navigationDestination(for: POSRoute.self) { route in
                destination(for: route)
            }
            .confirmationDialog("Начать новый чек?", isPresented: $confirmsNewReceipt, titleVisibility: .visible) {
                Button("Удалить текущий и начать новый", role: .destructive, action: startBlankReceipt)
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Позиции открытого чека на \(Money.format(cart.total)) будут удалены.")
            }
            .confirmationDialog(
                "Заменить открытый чек?",
                isPresented: Binding(get: { replacingFor != nil }, set: { if !$0 { replacingFor = nil } }),
                titleVisibility: .visible,
                presenting: replacingFor
            ) { appointment in
                Button("Открыть чек по записи", role: .destructive) { open(appointment) }
                Button("Отмена", role: .cancel) {}
            } message: { _ in
                Text("Позиции открытого чека на \(Money.format(cart.total)) будут удалены.")
            }
        }
        // On the stack (not the root content), so «Оплатить» works from the pushed receipt.
        .sheet(isPresented: $cart.isCheckoutPresented) {
            CheckoutView()
        }
        .onChange(of: cart.salesCompleted) {
            appState.closeReceipt()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: POSRoute.salesHistory) {
                Label("История продаж", systemImage: "clock.arrow.circlepath")
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: POSRoute.shiftsHistory) {
                Label("Смены", systemImage: "tray.full")
            }
        }
    }

    @ViewBuilder
    private func destination(for route: POSRoute) -> some View {
        switch route {
        case .receipt:
            ReceiptView(catalog: catalog)
        case .clientPicker:
            ClientPickerView(selection: Binding(get: { cart.client }, set: { cart.client = $0 }))
        case .salesHistory:
            SalesHistoryView()
        case .shiftsHistory:
            ShiftsHistoryView()
        }
    }

    // MARK: - Actions

    private var hasUnsavedWork: Bool {
        ReceiptDraft.hasUnsavedWork(lines: cart.lines, appointment: cart.appointment)
    }

    private func continueReceipt() {
        appState.posPath = [.receipt]
    }

    private func requestNewReceipt() {
        if hasUnsavedWork {
            confirmsNewReceipt = true
        } else {
            startBlankReceipt()
        }
    }

    private func startBlankReceipt() {
        cart.clear()
        appState.posPath = [.receipt]
    }

    private func select(_ appointment: Appointment) {
        if cart.appointmentId != appointment.id && hasUnsavedWork {
            replacingFor = appointment
        } else {
            open(appointment)
        }
    }

    private func open(_ appointment: Appointment) {
        cart.open(appointment)
        appState.posPath = [.receipt]
    }

    private func loadQueue() async {
        await queue.load { try await api.appointmentsAwaitingPayment() }
    }
}

#if DEBUG
#Preview {
    POSView()
        .previewEnvironment()
}
#endif
