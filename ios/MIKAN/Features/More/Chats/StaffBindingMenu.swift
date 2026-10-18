import SwiftUI

/// Toolbar menu of a non-staff chat: «Это сотрудник…» → an active employee → confirmation →
/// `PUT /bot/chats/:chatId/employee`. The bot then greets the employee as staff.
struct StaffBindingMenu: View {
    @Environment(APIClient.self) private var api
    @Environment(ReferenceStore.self) private var reference

    let chat: BotChat
    /// Called with the chat as the server returned it (now with `employee`).
    let onBound: (BotChat) -> Void

    @State private var pending: Employee?
    @State private var isBinding = false
    @State private var loadError: String?
    @State private var errorMessage: String?

    private var candidates: [Employee] { StaffBinding.candidates(from: reference.employees, for: chat) }

    var body: some View {
        Menu {
            Section("Это сотрудник…") {
                if let loadError {
                    Button("Повторить загрузку", systemImage: "arrow.clockwise") {
                        Task { await loadEmployees(force: true) }
                    }
                    Text(loadError)
                } else if candidates.isEmpty {
                    Text("Нет активных сотрудников")
                } else {
                    ForEach(candidates) { employee in
                        Button(employee.name, systemImage: "person") { pending = employee }
                    }
                }
            }
        } label: {
            if isBinding {
                ProgressView()
            } else {
                Label("Это сотрудник…", systemImage: "person.badge.shield.checkmark")
            }
        }
        .disabled(isBinding)
        .accessibilityHint("Привязать чат к сотруднику студии")
        .task { await loadEmployees(force: false) }
        .confirmationDialog(
            pending.map { "Это \($0.name)?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { employee in
            Button("Да, это \(employee.name)") { bind(employee) }
            Button("Отмена", role: .cancel) {}
        } message: { employee in
            Text(StaffBinding.confirmationMessage(employee: employee, chat: chat))
        }
        .errorAlert($errorMessage)
    }

    private func loadEmployees(force: Bool) async {
        do {
            try await reference.ensureEmployees(force: force)
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.userMessage
        }
    }

    private func bind(_ employee: Employee) {
        isBinding = true
        Task {
            defer { isBinding = false }
            do {
                let bound = try await api.bindChatEmployee(chatId: chat.chatId, employeeId: employee.id)
                withAnimation(.smooth) { onBound(bound) }
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        Text("Чат")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    StaffBindingMenu(chat: PreviewData.chat) { _ in }
                }
            }
    }
    .previewEnvironment()
}
#endif
