import SwiftUI

/// Remote value with loading / failure state. Keeps stale data visible while refreshing.
@Observable
final class Remote<Value> {
    private(set) var value: Value?
    private(set) var isLoading = false
    /// Failure while there is nothing to show (drives the error state).
    private(set) var failure: String?
    /// Failure of a refresh while stale data is visible (shown as an alert).
    var transientError: String?

    init(_ value: Value? = nil) {
        self.value = value
    }

    func load(_ operation: () async throws -> Value) async {
        isLoading = true
        if value == nil { failure = nil }
        defer { isLoading = false }
        do {
            value = try await operation()
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if value == nil {
                failure = error.userMessage
            } else {
                transientError = error.userMessage
            }
        }
    }

    func set(_ newValue: Value?) {
        value = newValue
        failure = nil
    }

    /// Applies a change to the loaded value (no-op when nothing is loaded).
    func update(_ transform: (Value) -> Value) {
        guard let value else { return }
        self.value = transform(value)
    }

    func reset() {
        value = nil
        failure = nil
        transientError = nil
    }
}

extension Remote where Value: RangeReplaceableCollection, Value.Element: Identifiable {
    /// Replaces the element with the same id, or inserts it at the front.
    func upsert(_ element: Value.Element) {
        update { items in
            var result = items
            if let index = result.firstIndex(where: { $0.id == element.id }) {
                result.replaceSubrange(index...index, with: [element])
            } else {
                result.insert(element, at: result.startIndex)
            }
            return result
        }
    }

    func remove(id: Value.Element.ID) {
        update { items in items.filter { $0.id != id } }
    }
}

/// Overlay for lists: spinner on first load, error with retry, or the empty state.
/// Keep the `List` itself in place so pull-to-refresh keeps working.
struct RemoteStateOverlay<Value, Empty: View>: View {
    let remote: Remote<Value>
    let isEmpty: (Value) -> Bool
    let retry: () async -> Void
    @ViewBuilder let empty: () -> Empty

    var body: some View {
        if let value = remote.value {
            if isEmpty(value) {
                empty()
            }
        } else if let failure = remote.failure {
            ErrorStateView(message: failure, retry: retry)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension RemoteStateOverlay where Value: Collection {
    init(remote: Remote<Value>, retry: @escaping () async -> Void, @ViewBuilder empty: @escaping () -> Empty) {
        self.init(remote: remote, isEmpty: { $0.isEmpty }, retry: retry, empty: empty)
    }
}

extension RemoteStateOverlay where Empty == EmptyView {
    /// For single-value screens with no empty state.
    init(remote: Remote<Value>, retry: @escaping () async -> Void) {
        self.init(remote: remote, isEmpty: { _ in false }, retry: retry, empty: { EmptyView() })
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label("Не удалось загрузить", systemImage: "exclamationmark.icloud")
        } description: {
            Text(message)
        } actions: {
            Button {
                Task {
                    isRetrying = true
                    await retry()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Повторить")
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isRetrying)
        }
    }
}

extension View {
    /// Alert showing a server/user error message verbatim.
    func errorAlert(_ message: Binding<String?>, title: String = "Ошибка") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// For writes whose result is unknown (timeout, dropped connection). They carry an `IdempotencyKey`,
    /// so «Повторить» resends the same request and the server never applies it twice.
    func retryAlert(_ message: Binding<String?>, title: String, retry: @escaping () -> Void) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("Повторить", action: retry)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// Shows refresh failures of a `Remote` while stale data stays on screen.
    func remoteErrorAlert<Value>(_ remote: Remote<Value>) -> some View {
        errorAlert(Binding(get: { remote.transientError }, set: { remote.transientError = $0 }))
    }
}
