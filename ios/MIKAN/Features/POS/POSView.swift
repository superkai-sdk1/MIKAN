import SwiftUI

/// «Касса» hub: shift card, the open receipts of every device with «Новый чек», today's visits not started yet.
/// Receipts are pushed onto `AppState.posPath`, so the schedule and the client card can land on them too.
struct POSView: View {
    @Environment(AppState.self) private var appState
    @Environment(APIClient.self) private var api
    @Environment(CartStore.self) private var cart
    @Environment(ShiftStore.self) private var shift
    @Environment(OpenReceiptsStore.self) private var receipts

    @State private var queue = Remote<[Appointment]>()
    @State private var catalog = Remote<[Product]>()
    @State private var opening: POSOpening?
    @State private var deletion: ReceiptDeletion?
    @State private var errorMessage: String?
    @State private var errorTitle = ""

    /// While the hub is on screen it refreshes this often, so receipts opened on other phones show up.
    private static let refreshInterval: Duration = .seconds(20)

    var body: some View {
        @Bindable var appState = appState
        @Bindable var cart = cart
        @Bindable var receipts = receipts
        NavigationStack(path: $appState.posPath) {
            List {
                ShiftCardView()
                    .hubRow(top: 4, bottom: 4)
                OpenReceiptsSection(
                    receipts: receipts.list,
                    cartReceiptId: cart.receiptId,
                    opening: opening,
                    retry: { await receipts.refresh() },
                    onOpen: open,
                    onDelete: { deletion = ReceiptDeletion($0) },
                    onNew: openNew
                )
                PaymentQueueSection(
                    queue: queue,
                    openReceipts: receipts.list.value ?? [],
                    opening: opening,
                    retry: loadQueue,
                    onStart: startVisit
                )
            }
            .listStyle(.plain)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .auraBackground()
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable {
                async let lists: Void = reload()
                async let shiftRefresh: Void = shift.refresh()
                _ = await (lists, shiftRefresh)
            }
            // Runs on every appearance (also when popping back from a receipt) and after each sale.
            .task(id: cart.salesCompleted) {
                await reload()
                if !shift.hasLoaded { await shift.refresh() }
                await pollWhileVisible()
            }
            .remoteErrorAlert(queue)
            .remoteErrorAlert(receipts.list)
            .receiptDeletionDialog($deletion, onDelete: delete)
            .navigationTitle("Касса")
            .toolbar { toolbarContent }
            .navigationDestination(for: POSRoute.self) { route in
                destination(for: route)
            }
        }
        // On the stack (not the root content), so «Оплатить» works from the pushed receipt.
        .sheet(isPresented: $cart.isCheckoutPresented) {
            CheckoutView()
        }
        .background { ReceiptAutosave() }
        .errorAlert($errorMessage, title: errorTitle)
        .errorAlert($receipts.goneNotice, title: "Чек закрыт")
        .onChange(of: cart.salesCompleted) {
            appState.closeReceipt()
        }
        .onChange(of: receipts.goneNotice) { _, notice in
            if notice != nil { appState.closeReceipt() }
        }
        .onChange(of: appState.posPath) { old, new in
            // Leaving the receipt screen saves it at once; a «Новый чек» left empty is deleted.
            guard old.contains(.receipt), !new.contains(.receipt) else { return }
            Task { await receipts.leave() }
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

    private func open(_ receipt: OpenReceipt) {
        run(.receipt(receipt.id)) { try await receipts.open(receipt) }
    }

    private func openNew() {
        run(.newReceipt) { try await receipts.openNew() }
    }

    /// «Начать визит»: the appointment moves to the open receipts (or joins the receipt another phone started).
    private func startVisit(_ appointment: Appointment) {
        run(.visit(appointmentId: appointment.id)) { try await appState.startCheckout(for: appointment) }
    }

    /// One receipt is opened at a time; on success its screen is pushed.
    private func run(_ target: POSOpening, _ operation: @escaping () async throws -> Void) {
        guard opening == nil else { return }
        opening = target
        Task {
            defer { opening = nil }
            do {
                try await operation()
                appState.showReceipt()
            } catch is CancellationError {
                return
            } catch {
                showError(error.userMessage, title: "Чек не открыт")
            }
        }
    }

    private func delete(_ deletion: ReceiptDeletion) {
        Task {
            do {
                try await appState.deleteReceipt(id: deletion.id, hasAppointment: deletion.hasAppointment)
                // The appointment is back among the unpaid ones.
                if deletion.hasAppointment { await loadQueue() }
            } catch {
                showError(error.userMessage, title: "Чек не удалён")
            }
        }
    }

    private func showError(_ message: String, title: String) {
        errorTitle = title
        errorMessage = message
    }

    // MARK: - Loading

    private func reload() async {
        async let receiptsLoad: Void = receipts.refresh()
        async let queueLoad: Void = loadQueue()
        _ = await (receiptsLoad, queueLoad)
    }

    private func loadQueue() async {
        await queue.load { try await api.appointmentsAwaitingPayment() }
    }

    /// Quiet refreshes until the hub disappears (a pushed receipt or another tab cancels the task).
    private func pollWhileVisible() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.refreshInterval)
            guard !Task.isCancelled else { return }
            async let receiptsLoad: Void = receipts.refreshQuietly()
            async let queueLoad: Void = refreshQueueQuietly()
            _ = await (receiptsLoad, queueLoad)
        }
    }

    /// Polling failures are not shown: the next pull-to-refresh reports them.
    private func refreshQueueQuietly() async {
        guard let appointments = try? await api.appointmentsAwaitingPayment() else { return }
        queue.set(appointments)
    }
}

/// Saves the cart's receipt shortly after each change (see `OpenReceiptsStore`). It sits behind the POS stack, so
/// edits on the receipt screen, in the client picker and in checkout are all caught.
private struct ReceiptAutosave: View {
    @Environment(CartStore.self) private var cart
    @Environment(OpenReceiptsStore.self) private var receipts

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .onChange(of: cart.makeReceiptBody()) {
                receipts.cartDidChange()
            }
    }
}

#if DEBUG
#Preview {
    POSView()
        .previewEnvironment()
}
#endif
