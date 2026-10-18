import XCTest
@testable import MIKAN

extension Fixtures {
    /// The Product example of docs/API.md: a labret in two sizes.
    static let productWithSizes = #"""
    { "id": 1, "kind": "jewelry", "name": "Лабрет", "sku": "LB-12", "category": "Лабрет",
      "material": "Титан ASTM F136", "threadType": "internal", "thicknessMm": 1.2,
      "color": "Серебристый", "stone": "Фианит", "supplier": "Industrial Strength",
      "description": "Описание", "price": 1500, "cost": 600, "unit": "шт",
      "photos": ["/uploads/3f1c.jpg", "/uploads/9a0b.jpg"], "photoUrl": "/uploads/3f1c.jpg",
      "serviceIds": [3, 7], "active": true,
      "variants": [
        { "id": 1, "name": "6 мм", "sku": null, "price": null, "cost": null,
          "quantity": 4, "minQuantity": 1, "lowStock": false },
        { "id": 5, "name": "8 мм", "sku": "LB-12-08", "price": 1700, "cost": 700,
          "quantity": 0, "minQuantity": 1, "lowStock": true } ],
      "quantity": 4, "minQuantity": 2, "lowStock": true, "size": "6 мм, 8 мм",
      "createdAt": "<T>", "updatedAt": "<T>" }
    """#

    static let movementWithSize = #"""
    { "id": 2, "productId": 1, "productName": "Лабрет", "variantId": 5, "variantName": "8 мм",
      "delta": 3, "quantityAfter": 3, "type": "receipt", "note": "Поставка", "saleId": null, "appointmentId": null,
      "employee": { "id": 1, "name": "Анна", "color": "#FF7A1A" }, "createdAt": "<T>" }
    """#
}

/// Sizes of jewelry: decoding the API shapes (and those of a server without sizes), derived totals and texts.
final class ProductVariantsTests: XCTestCase {
    func testProductWithSizesDecodes() throws {
        for fractional in [true, false] {
            let product = try Fixtures.decode(Product.self, Fixtures.productWithSizes, fractional: fractional)
            XCTAssertEqual(product.variants.map(\.name), ["6 мм", "8 мм"])
            XCTAssertEqual(product.threadType, .internalThread)
            XCTAssertEqual(product.thicknessMm, 1.2)
            XCTAssertEqual(product.photos, ["/uploads/3f1c.jpg", "/uploads/9a0b.jpg"])
            XCTAssertEqual(product.photoUrl, "/uploads/3f1c.jpg")
            XCTAssertEqual(product.serviceIds, [3, 7])
            XCTAssertEqual(product.quantity, 4)
            XCTAssertEqual(product.minQuantity, 2)
            XCTAssertTrue(product.lowStock, "the 8 mm size is out")
            XCTAssertEqual(product.lowVariants.map(\.id), [5])
            XCTAssertEqual(product.availableVariants.map(\.id), [1])
            XCTAssertTrue(product.hasSeveralSizes)
            XCTAssertEqual(product.size, "6 мм, 8 мм")
        }
    }

    func testLegacyProductBecomesOneSize() throws {
        let product = try Fixtures.decode(Product.self, Fixtures.product)
        XCTAssertEqual(product.variants.count, 1)
        let only = try XCTUnwrap(product.variants.first)
        XCTAssertEqual(only.id, product.id, "matches the variant the server migration creates")
        XCTAssertEqual(only.name, "1.2×8 мм")
        XCTAssertEqual(only.quantity, 12)
        XCTAssertEqual(only.minQuantity, 3)
        XCTAssertFalse(product.hasSeveralSizes)
        XCTAssertEqual(product.photos, ["/uploads/3f1c.jpg"])
        XCTAssertEqual(product.serviceIds, [])
        XCTAssertNil(product.threadType)
    }

    func testUnknownThreadTypeIsIgnored() throws {
        let json = Fixtures.productWithSizes.replacingOccurrences(of: #""threadType": "internal""#, with: #""threadType": "magnetic""#)
        XCTAssertNil(try Fixtures.decode(Product.self, json).threadType)
    }

    func testSizePricesFallBackToTheProduct() throws {
        let product = try Fixtures.decode(Product.self, Fixtures.productWithSizes)
        let six = try XCTUnwrap(product.variant(id: 1))
        let eight = try XCTUnwrap(product.variant(id: 5))
        XCTAssertEqual(product.price(of: six), 1500)
        XCTAssertEqual(product.price(of: eight), 1700)
        XCTAssertEqual(product.cost(of: six), 600)
        XCTAssertEqual(product.cost(of: eight), 700)
        XCTAssertEqual(product.sku(of: six), "LB-12")
        XCTAssertEqual(product.sku(of: eight), "LB-12-08")
        XCTAssertEqual(product.priceRange, 1500...1700)
        XCTAssertEqual(product.priceText, "от 1\u{00A0}500\u{00A0}₽")
    }

    func testLineNamesMatchTheServer() throws {
        let product = try Fixtures.decode(Product.self, Fixtures.productWithSizes)
        XCTAssertEqual(product.lineName(variant: product.variant(id: 5)), "Лабрет — 8 мм")
        XCTAssertEqual(product.lineName(variant: nil), "Лабрет")
        var unnamed = product
        unnamed.variants = [ProductVariant(id: 9, name: " ", sku: nil, price: nil, cost: nil, quantity: 1, minQuantity: 0, lowStock: false)]
        XCTAssertEqual(unnamed.lineName(variant: unnamed.variants.first), "Лабрет")
        XCTAssertNil(unnamed.size)
    }

    func testDetailLineShowsTheSizeOnlyForASingleSize() throws {
        let product = try Fixtures.decode(Product.self, Fixtures.productWithSizes)
        XCTAssertEqual(product.detailLine, "Титан ASTM F136 · 1.2\u{00A0}мм\u{00A0}(16G)")
        XCTAssertEqual(product.sizesSummary, "6 мм · 8 мм")
    }

    func testGaugeLabels() {
        XCTAssertEqual(Gauge.label(forMillimeters: 1.2), "16G")
        XCTAssertEqual(Gauge.label(forMillimeters: 1.6), "14G")
        XCTAssertEqual(Gauge.label(forMillimeters: 8), "0G")
        XCTAssertNil(Gauge.label(forMillimeters: 1.3))
        XCTAssertEqual(Gauge.thicknessText(1.2), "1.2\u{00A0}мм\u{00A0}(16G)")
        XCTAssertEqual(Gauge.thicknessText(1), "1\u{00A0}мм\u{00A0}(18G)")
        XCTAssertEqual(Gauge.thicknessText(1.25), "1.25\u{00A0}мм")
        XCTAssertEqual(Gauge.parse("1,2"), 1.2)
        XCTAssertEqual(Gauge.parse("1.6 мм"), 1.6)
        XCTAssertNil(Gauge.parse(""))
        XCTAssertNil(Gauge.parse("0"))
    }

    func testMovementWithSize() throws {
        let movement = try Fixtures.decode(StockMovement.self, Fixtures.movementWithSize)
        XCTAssertEqual(movement.variantId, 5)
        XCTAssertEqual(movement.displayName, "Лабрет — 8 мм")
        let legacy = try Fixtures.decode(StockMovement.self, Fixtures.stockMovement)
        XCTAssertNil(legacy.variantId)
        XCTAssertEqual(legacy.displayName, "Лабрет")

        let batch = try Fixtures.decode(
            BatchMovementResult.self,
            #"{ "product": \#(Fixtures.productWithSizes), "movements": [\#(Fixtures.movementWithSize)] }"#
        )
        XCTAssertEqual(batch.movements.map(\.quantityAfter), [3])
    }

    func testSaleItemAndHistoryCarryTheSize() throws {
        let json = Fixtures.sale.replacingOccurrences(
            of: #""productId": 1, "serviceId": null,"#,
            with: #""productId": 1, "variantId": 5, "variantName": "8 мм", "serviceId": null,"#
        )
        let sale = try Fixtures.decode(Sale.self, json)
        XCTAssertEqual(sale.items.first?.variantId, 5)
        XCTAssertEqual(sale.items.first?.variantName, "8 мм")
        XCTAssertNil(try Fixtures.decode(Sale.self, Fixtures.sale).items.first?.variantId, "sales made before sizes")
    }

    func testTopProductsSplitBySize() throws {
        let json = Fixtures.report.replacingOccurrences(
            of: #""revenue": 10500 }"#,
            with: #""revenue": 10500, "variants": [ { "variantId": 5, "name": "8 мм", "quantity": 4, "revenue": 6000 } ] }"#
        )
        let report = try Fixtures.decode(ReportSummary.self, json)
        XCTAssertEqual(report.topProducts.first?.variants.map(\.name), ["8 мм"])
        XCTAssertEqual(try Fixtures.decode(ReportSummary.self, Fixtures.report).topProducts.first?.variants, [])
    }

    func testBodiesEncodeSizes() throws {
        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let batch = StockBatchBody(type: .receipt, note: nil, lines: [StockLineBody(variantId: 5, quantity: 3)])
        XCTAssertEqual(
            String(decoding: try encoder.encode(batch), as: UTF8.self),
            #"{"lines":[{"quantity":3,"variantId":5}],"type":"receipt"}"#
        )
        let item = SaleItemBody(type: .product, productId: 1, serviceId: nil, name: nil, quantity: 1, price: 1700, variantId: 5)
        let encoded = String(decoding: try encoder.encode(item), as: UTF8.self)
        XCTAssertTrue(encoded.contains(#""variantId":5"#))
        let newSize = ProductVariantBody(id: nil, name: "10 мм", sku: nil, price: Nullable(1700), cost: nil, minQuantity: 1, initialQuantity: 2)
        XCTAssertEqual(
            String(decoding: try encoder.encode(newSize), as: UTF8.self),
            #"{"cost":null,"initialQuantity":2,"minQuantity":1,"name":"10 мм","price":1700,"sku":null}"#
        )
    }
}
