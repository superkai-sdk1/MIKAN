import Foundation

// MARK: - Services, aftercare templates, products, stock, uploads

extension APIClient {
    func services(includeInactive: Bool = false) async throws -> [Service] {
        let response: ItemsResponse<Service> = try await request(
            .get, "services",
            query: queryItems(["includeInactive": includeInactive ? "true" : nil])
        )
        return response.items
    }

    func createService(_ body: ServiceBody) async throws -> Service {
        try await request(.post, "services", body: body)
    }

    func updateService(id: Int, _ body: ServiceBody) async throws -> Service {
        try await request(.patch, "services/\(id)", body: body)
    }

    /// Who got this service and when, newest first.
    func serviceHistory(id: Int, limit: Int = 50, offset: Int = 0) async throws -> ItemsResponse<HistoryEntry> {
        try await request(.get, "services/\(id)/history", query: queryItems([
            "limit": String(limit),
            "offset": String(offset),
        ]))
    }

    /// Generates the schematic cover with AI (takes 1–2 minutes).
    func generateServiceImage(id: Int, prompt: String?) async throws -> Service {
        try await request(
            .post, "services/\(id)/image/generate",
            body: GenerateImageBody(prompt: prompt.nonEmpty),
            timeout: Self.imageGenerationTimeout
        )
    }

    func aftercareTemplates() async throws -> [AftercareTemplate] {
        let response: ItemsResponse<AftercareTemplate> = try await request(.get, "aftercare-templates")
        return response.items
    }

    func createAftercareTemplate(_ body: AftercareTemplateBody) async throws -> AftercareTemplate {
        try await request(.post, "aftercare-templates", body: body)
    }

    func updateAftercareTemplate(id: Int, _ body: AftercareTemplateBody) async throws -> AftercareTemplate {
        try await request(.patch, "aftercare-templates/\(id)", body: body)
    }

    func deleteAftercareTemplate(id: Int) async throws {
        try await requestVoid(.delete, "aftercare-templates/\(id)")
    }

    func products(
        kind: ProductKind? = nil,
        search: String = "",
        lowStock: Bool = false,
        includeInactive: Bool = false
    ) async throws -> [Product] {
        let response: ItemsResponse<Product> = try await request(.get, "products", query: queryItems([
            "kind": kind?.rawValue,
            "search": search.nonEmpty,
            "lowStock": lowStock ? "true" : nil,
            "includeInactive": includeInactive ? "true" : nil,
        ]))
        return response.items
    }

    func product(id: Int) async throws -> Product {
        try await request(.get, "products/\(id)")
    }

    func createProduct(_ body: ProductBody) async throws -> Product {
        try await request(.post, "products", body: body)
    }

    func updateProduct(id: Int, _ body: ProductBody) async throws -> Product {
        try await request(.patch, "products/\(id)", body: body)
    }

    func addMovement(productId: Int, _ body: MovementBody, idempotencyKey: UUID) async throws -> MovementResult {
        try await request(.post, "products/\(productId)/movements", body: body, idempotencyKey: idempotencyKey)
    }

    /// One operation over several sizes in one transaction.
    func addMovements(productId: Int, _ body: StockBatchBody, idempotencyKey: UUID) async throws -> BatchMovementResult {
        try await request(.post, "products/\(productId)/movements/batch", body: body, idempotencyKey: idempotencyKey)
    }

    /// Movements of the product, or of one size.
    func productMovements(
        productId: Int,
        variantId: Int? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> ItemsResponse<StockMovement> {
        try await request(.get, "products/\(productId)/movements", query: queryItems([
            "variantId": variantId.map(String.init),
            "limit": String(limit),
            "offset": String(offset),
        ]))
    }

    /// Who bought this product (or one size of it) and when, newest first.
    func productHistory(
        id: Int,
        variantId: Int? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> ItemsResponse<HistoryEntry> {
        try await request(.get, "products/\(id)/history", query: queryItems([
            "variantId": variantId.map(String.init),
            "limit": String(limit),
            "offset": String(offset),
        ]))
    }

    func stockMovements(type: MovementType? = nil, limit: Int = 50, offset: Int = 0) async throws -> ItemsResponse<StockMovement> {
        try await request(.get, "stock/movements", query: queryItems([
            "type": type?.rawValue,
            "limit": String(limit),
            "offset": String(offset),
        ]))
    }
}
