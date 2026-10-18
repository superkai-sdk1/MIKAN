import SwiftUI

/// Texts of «Удалить «Лабрет»?» and whether the stock left is written off first (`DELETE /products/:id?writeOff=true`).
nonisolated struct ProductDeleteConfirmation: Hashable, Sendable {
    let title: String
    let message: String
    let buttonTitle: String
    /// Some stock is left: the server deletes only after writing it off.
    let writesOff: Bool

    private static let base = "Позиция пропадёт со склада, из кассы и у бота. Продажи и история движений сохранятся."

    init(product: Product) {
        title = "Удалить «\(product.name)»?"
        // A consumable tracked as «есть / нет» may keep counted stock aside; it is written off too, but never shown.
        writesOff = product.quantity > 0
        if writesOff, !product.isPresenceTracked {
            let stock = InventoryText.quantity(product.quantity, unit: product.unitLabel)
            message = "\(Self.base) На складе \(stock) — остаток будет списан."
            buttonTitle = "Списать остаток и удалить"
        } else {
            message = Self.base
            buttonTitle = "Удалить"
        }
    }
}

extension View {
    /// Asks «Удалить «Лабрет»?» while `isPresented` and deletes the product; `onDeleted` runs once it is gone (also when
    /// it already was). Errors go to `errorMessage`.
    func productDeletion(
        _ product: Product?,
        isPresented: Binding<Bool>,
        isDeleting: Binding<Bool>,
        errorMessage: Binding<String?>,
        onDeleted: @escaping (Int) -> Void
    ) -> some View {
        modifier(ProductDeletionModifier(
            product: product,
            isPresented: isPresented,
            isDeleting: isDeleting,
            errorMessage: errorMessage,
            onDeleted: onDeleted
        ))
    }
}

private struct ProductDeletionModifier: ViewModifier {
    @Environment(APIClient.self) private var api
    let product: Product?
    @Binding var isPresented: Bool
    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onDeleted: (Int) -> Void

    func body(content: Content) -> some View {
        let confirmation = product.map(ProductDeleteConfirmation.init(product:))
        content.confirmationDialog(confirmation?.title ?? "", isPresented: $isPresented, titleVisibility: .visible) {
            if let confirmation {
                Button(confirmation.buttonTitle, role: .destructive) { delete(writeOff: confirmation.writesOff) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            if let confirmation { Text(confirmation.message) }
        }
    }

    private func delete(writeOff: Bool) {
        guard let id = product?.id, !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                _ = try await api.deleteProduct(id: id, writeOff: writeOff)
                onDeleted(id)
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}
