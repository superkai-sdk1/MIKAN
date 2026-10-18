import XCTest
@testable import MIKAN

private typealias F = InventoryFixtures
private let nbsp = "\u{00A0}"

/// The product editor: validation like the server's, the API body (sizes kept / added / removed), size and photo
/// operations, and the texts of the product card.
final class ProductDraftTests: XCTestCase {
    // MARK: - Starting state

    func testNewDraftHasOneUnnamedSize() {
        let draft = ProductDraft(product: nil, defaultKind: .jewelry)
        XCTAssertTrue(draft.isNew)
        XCTAssertEqual(draft.kind, .jewelry)
        XCTAssertEqual(draft.unit, "шт")
        XCTAssertTrue(draft.active)
        XCTAssertEqual(draft.sizes.count, 1)
        XCTAssertNil(draft.sizes[0].variantId)
        XCTAssertEqual(draft.sizes[0].name, "")
        XCTAssertEqual(draft.nameMessage, "Укажите название.")
        XCTAssertFalse(draft.canSave)
    }

    func testDraftFromProductKeepsItsSizesAndAttributes() {
        let draft = ProductDraft(product: F.labret)
        XCTAssertEqual(draft.productId, 1)
        XCTAssertEqual(draft.sizes.map(\.variantId), [1, 4, 5])
        XCTAssertEqual(draft.sizes.map(\.name), ["6 мм", "8 мм", "10 мм"])
        XCTAssertEqual(draft.sizes.map(\.quantity), [4, 1, 0])
        XCTAssertEqual(draft.sizes[2].sku, "LB-12-10")
        XCTAssertEqual(draft.sizes[2].price, 1_700)
        XCTAssertEqual(draft.thicknessText, "1.2")
        XCTAssertEqual(draft.threadType, .internalThread)
        XCTAssertEqual(draft.serviceIds, [3])
        XCTAssertNil(draft.validationMessage)
    }

    // MARK: - Validation

    func testRequiredFields() {
        var draft = ProductDraft(product: F.labret)
        draft.name = "   "
        XCTAssertEqual(draft.validationMessage, "Укажите название.")
        draft.name = "Лабрет"
        draft.unit = " "
        XCTAssertEqual(draft.validationMessage, "Укажите единицу измерения.")
    }

    func testSizeNamesMustBeUnique() {
        var draft = ProductDraft(product: F.labret)
        draft.sizes[2].name = " 8 ММ "
        XCTAssertEqual(draft.validationMessage, "Размер «8 ММ» указан дважды.", "trimmed and case-insensitive")
        draft.sizes[2].name = "12 мм"
        XCTAssertNil(draft.validationMessage)
    }

    func testEverySizeNeedsANameWhenThereAreSeveral() {
        let draft = ProductDraft(product: nil, defaultKind: .jewelry).addingSize()
        var named = draft
        named.name = "Лабрет"
        XCTAssertEqual(named.validationMessage, "Укажите название у каждого размера.")
        named.sizes[0].name = "6 мм"
        XCTAssertEqual(named.validationMessage, "Укажите название у каждого размера.")
        named.sizes[1].name = "8 мм"
        XCTAssertNil(named.validationMessage)
    }

    func testOneUnnamedSizeIsAProductWithoutSizes() {
        var draft = ProductDraft(product: nil, defaultKind: .jewelry)
        draft.name = "Банан"
        XCTAssertNil(draft.validationMessage)
        XCTAssertFalse(draft.hasSeveralSizes)
    }

    func testConsumableHasExactlyOneSize() {
        var draft = ProductDraft(product: F.labret)
        draft.kind = .consumable
        XCTAssertEqual(
            draft.validationMessage,
            "У расходника только один размер — удалите лишние или выберите тип «Украшение»."
        )
        XCTAssertTrue(draft.showsSizesEditor, "the editor stays to remove the extra sizes")

        var consumable = ProductDraft(product: nil, defaultKind: .consumable)
        consumable.name = "Иглы"
        XCTAssertNil(consumable.validationMessage)
        XCTAssertFalse(consumable.showsSizesEditor)
    }

    func testSizesLimit() {
        var draft = ProductDraft(product: nil, defaultKind: .jewelry)
        draft.name = "Лабрет"
        draft.sizes = (1...51).map { SizeDraft(name: "\($0) мм") }
        XCTAssertEqual(draft.validationMessage, "Не больше 50 размеров.")
    }

    func testThicknessParsing() {
        XCTAssertEqual(ProductDraft.parseThickness("1,2"), 1.2)
        XCTAssertEqual(ProductDraft.parseThickness("1.2 мм"), 1.2)
        XCTAssertEqual(ProductDraft.parseThickness("16G"), 1.2, "a gauge from the table")
        XCTAssertEqual(ProductDraft.parseThickness("14g"), 1.6)
        XCTAssertNil(ProductDraft.parseThickness("15G"), "not a gauge the studio uses")
        XCTAssertNil(ProductDraft.parseThickness(""))
        XCTAssertNil(ProductDraft.parseThickness("толстая"))
    }

    func testThicknessValidationAndHint() {
        var draft = ProductDraft(product: F.labret)
        draft.thicknessText = ""
        XCTAssertNil(draft.thicknessMessage, "optional")
        XCTAssertNil(draft.thicknessHint)

        draft.thicknessText = "1,6"
        XCTAssertNil(draft.thicknessMessage)
        XCTAssertEqual(draft.thicknessHint, "1.6\u{00A0}мм\u{00A0}(14G)")
        XCTAssertEqual(draft.body.thicknessMm, Nullable(1.6))

        draft.thicknessText = "толстая"
        XCTAssertEqual(draft.validationMessage, "Толщина — миллиметры (1.2) или калибр (16G).")

        draft.thicknessText = "35"
        XCTAssertEqual(draft.validationMessage, "Толщина — не больше 30 мм.")

        draft.kind = .consumable
        draft.sizes = [draft.sizes[0]]
        XCTAssertNil(draft.thicknessMessage, "consumables have no thickness")
    }

    func testTextLimits() {
        var draft = ProductDraft(product: F.labret)
        draft.color = String(repeating: "а", count: 101)
        XCTAssertEqual(draft.validationMessage, "Цвет — не длиннее 100 символов.")
        draft.color = ""
        draft.supplier = String(repeating: "б", count: 101)
        XCTAssertEqual(draft.validationMessage, "Поставщик — не длиннее 100 символов.")
    }

    func testPhotoAndServiceLimits() {
        var draft = ProductDraft(product: F.labret)
        draft.photos = (1...11).map { "/uploads/\($0).jpg" }
        XCTAssertEqual(draft.validationMessage, "Не больше 10 фото.")
        draft.photos = []
        draft.serviceIds = Array(1...31)
        XCTAssertEqual(draft.validationMessage, "Не больше 30 услуг.")
    }

    // MARK: - Body

    func testBodyKeepsIdsAddsNewSizesAndOmitsRemovedOnes() throws {
        let start = ProductDraft(product: F.labret)
        let ten = try XCTUnwrap(start.sizes.first { $0.variantId == 5 }).id
        var draft = start.removingSize(ten).addingSizes(named: ["12 мм"])
        draft.sizes[2].initialQuantity = 3
        draft.sizes[0].minQuantity = 2
        draft = draft.movingSize(draft.sizes[2].id, by: -1)

        let variants = draft.body.variants
        XCTAssertEqual(variants.map(\.id), [1, nil, 4], "list order; the 10 мм size is left out")
        XCTAssertEqual(variants.map(\.name), ["6 мм", "12 мм", "8 мм"])
        XCTAssertEqual(variants.map(\.initialQuantity), [nil, 3, nil], "only a new size carries its initial stock")
        XCTAssertEqual(variants[0].minQuantity, 2)
        XCTAssertEqual(variants[2].sku, Nullable("LB-12-08"))

        let json = try encoded(draft.body)
        let sizes = try XCTUnwrap(json["variants"] as? [[String: Any]])
        XCTAssertEqual(sizes[0]["id"] as? Int, 1)
        XCTAssertNil(sizes[1]["id"], "a new size has no id")
        XCTAssertEqual(sizes[1]["initialQuantity"] as? Int, 3)
        XCTAssertNil(sizes[0]["initialQuantity"])
        XCTAssertTrue(sizes[0]["price"] is NSNull, "the product's price")
    }

    func testOwnValuesOfASize() {
        var draft = ProductDraft(product: F.labret)
        draft.sizes[0].sku = "  LB-12-06 "
        draft.sizes[1].sku = "   "
        let variants = draft.body.variants
        XCTAssertEqual(variants[0].sku, Nullable("LB-12-06"))
        XCTAssertEqual(variants[1].sku, Nullable(nil), "blank = the product's article")
        XCTAssertEqual(variants[2].price, Nullable(1_700))
        XCTAssertEqual(variants[2].cost, Nullable(700))
        XCTAssertTrue(draft.sizes[0].hasOwnValues)
        XCTAssertFalse(draft.sizes[1].hasOwnValues)
        XCTAssertTrue(draft.sizes[2].hasOwnValues)
    }

    func testJewelryBodyCarriesTheAttributes() {
        var draft = ProductDraft(product: F.labret)
        draft.name = "  Лабрет  "
        draft.sku = " "
        draft.serviceIds = [3, 7]
        let body = draft.body
        XCTAssertEqual(body.name, "Лабрет")
        XCTAssertEqual(body.sku, Nullable(nil))
        XCTAssertEqual(body.material, Nullable("Титан ASTM F136"))
        XCTAssertEqual(body.threadType, Nullable(.internalThread))
        XCTAssertEqual(body.thicknessMm, Nullable(1.2))
        XCTAssertEqual(body.color, Nullable("Серебристый"))
        XCTAssertEqual(body.stone, Nullable("Фианит"))
        XCTAssertEqual(body.supplier, Nullable("Industrial Strength"))
        XCTAssertEqual(body.serviceIds, [3, 7])
        XCTAssertEqual(body.price, 1_500)
        XCTAssertEqual(body.cost, Nullable(600))
    }

    func testConsumableBodyHasOneUnnamedSizeAndNoJewelryFields() {
        var draft = ProductDraft(product: nil, defaultKind: .consumable)
        draft.name = "Иглы 1.2 мм"
        draft.material = "Сталь"
        draft.threadType = .threadless
        draft.thicknessText = "1.2"
        draft.color = "Серый"
        draft.serviceIds = [3]
        draft.sizes[0].initialQuantity = 100
        draft.sizes[0].minQuantity = 20

        let body = draft.body
        XCTAssertEqual(body.kind, .consumable)
        XCTAssertEqual(body.material, Nullable("Сталь"), "material stays for consumables")
        XCTAssertEqual(body.threadType, Nullable(nil))
        XCTAssertEqual(body.thicknessMm, Nullable(nil))
        XCTAssertEqual(body.color, Nullable(nil))
        XCTAssertEqual(body.serviceIds, [])
        XCTAssertEqual(body.variants, [
            ProductVariantBody(id: nil, name: "", sku: nil, price: nil, cost: nil, minQuantity: 20, initialQuantity: 100),
        ])
    }

    func testLegacyProductWithoutSizesKeepsItsOnlySize() {
        let legacy = F.product(id: 7, name: "Кольцо", quantity: 12, minQuantity: 3)
        let draft = ProductDraft(product: legacy)
        XCTAssertEqual(draft.body.variants, [
            ProductVariantBody(id: 7, name: "", sku: nil, price: nil, cost: nil, minQuantity: 3, initialQuantity: nil),
        ])
    }

    func testNegativeNumbersAreSentAsZero() {
        var draft = ProductDraft(product: F.labret)
        draft.price = -5
        draft.cost = -1
        draft.sizes[0].minQuantity = -2
        XCTAssertEqual(draft.body.price, 0)
        XCTAssertEqual(draft.body.cost, Nullable(0))
        XCTAssertEqual(draft.body.variants[0].minQuantity, 0)
    }

    // MARK: - Size operations

    func testSizeWithStockCannotBeRemoved() {
        let draft = ProductDraft(product: F.labret)
        let six = draft.sizes[0].id
        XCTAssertEqual(draft.removalBlock(for: six), "На складе 4 шт — сначала спишите остаток.")
        XCTAssertEqual(draft.removingSize(six), draft)

        let ten = draft.sizes[2].id
        XCTAssertNil(draft.removalBlock(for: ten), "an empty size can go")
        XCTAssertEqual(draft.removingSize(ten).sizes.map(\.variantId), [1, 4])
    }

    func testLastSizeStays() {
        let draft = ProductDraft(product: nil, defaultKind: .jewelry)
        XCTAssertEqual(draft.removalBlock(for: draft.sizes[0].id), "Должен остаться хотя бы один размер.")
        XCTAssertEqual(draft.removingSize(draft.sizes[0].id).sizes.count, 1)
    }

    func testAddingSizesFillsTheUnnamedSizeFirst() {
        let start = ProductDraft(product: nil, defaultKind: .jewelry)
        let draft = start.addingSizes(named: ["6 мм", "8 мм", "6 ММ", "10 мм"])
        XCTAssertEqual(draft.sizes.map(\.name), ["6 мм", "8 мм", "10 мм"], "no empty row is left, repeats are skipped")
        XCTAssertEqual(draft.sizes[0].id, start.sizes[0].id)

        let more = draft.addingSizes(named: ["8 мм", "12 мм"])
        XCTAssertEqual(more.sizes.map(\.name), ["6 мм", "8 мм", "10 мм", "12 мм"])
        XCTAssertEqual(more.addingSizes(named: ["8 мм"]), more)
    }

    func testAddedSizeStartsWithTheLastMinimum() {
        var draft = ProductDraft(product: F.labret)
        draft.sizes[2].minQuantity = 3
        XCTAssertEqual(draft.addingSize().sizes.last?.minQuantity, 3)
        XCTAssertTrue(draft.addingSize().sizes.last?.isNew == true)
    }

    func testMovingSizes() {
        let draft = ProductDraft(product: F.labret)
        let ten = draft.sizes[2].id
        XCTAssertEqual(draft.movingSize(ten, by: -1).sizes.map(\.variantId), [1, 5, 4])
        XCTAssertEqual(draft.movingSize(ten, by: 5).sizes.map(\.variantId), [1, 4, 5], "clamped")
        XCTAssertEqual(draft.movingSizes(fromOffsets: [0], toOffset: 3).sizes.map(\.variantId), [4, 5, 1])
        XCTAssertEqual(draft.movingSizes(fromOffsets: [2], toOffset: 0).sizes.map(\.variantId), [5, 1, 4])
    }

    // MARK: - Photos and services

    func testPhotoOperations() {
        var draft = ProductDraft(product: F.labret)
        draft.photos = ["/a.jpg", "/b.jpg", "/c.jpg"]
        XCTAssertEqual(draft.makingCover("/c.jpg").photos, ["/c.jpg", "/a.jpg", "/b.jpg"])
        XCTAssertEqual(draft.movingPhoto("/a.jpg", by: 1).photos, ["/b.jpg", "/a.jpg", "/c.jpg"])
        XCTAssertEqual(draft.removingPhoto("/b.jpg").photos, ["/a.jpg", "/c.jpg"])
        XCTAssertEqual(draft.addingPhotos(["/a.jpg", "/d.jpg"]).photos, ["/a.jpg", "/b.jpg", "/c.jpg", "/d.jpg"])

        draft.photos = (1...9).map { "/\($0).jpg" }
        XCTAssertEqual(draft.remainingPhotos, 1)
        XCTAssertEqual(draft.addingPhotos(["/x.jpg", "/y.jpg"]).photos.count, 10, "never more than 10")
    }

    func testTogglingServices() {
        let draft = ProductDraft(product: F.labret)
        XCTAssertEqual(draft.togglingService(7).serviceIds, [3, 7])
        XCTAssertEqual(draft.togglingService(3).serviceIds, [])
    }

    // MARK: - Texts

    func testSizeNamesFromOneLine() {
        XCTAssertEqual(ProductSizeNames.parse("6, 8, 10 мм"), ["6 мм", "8 мм", "10 мм"])
        XCTAssertEqual(ProductSizeNames.parse("S; M; L"), ["S", "M", "L"])
        XCTAssertEqual(ProductSizeNames.parse("1.2×6, 1.2×8 мм"), ["1.2×6 мм", "1.2×8 мм"])
        XCTAssertEqual(ProductSizeNames.parse("6 мм\n8 мм\n"), ["6 мм", "8 мм"])
        XCTAssertEqual(ProductSizeNames.parse("6, 6 мм, 8"), ["6", "6 мм", "8"], "the last name has no unit to share")
        XCTAssertEqual(ProductSizeNames.parse("6, 8 мм, 8 мм"), ["6 мм", "8 мм"])
        XCTAssertEqual(ProductSizeNames.parse(" , "), [])
    }

    func testMarkup() {
        XCTAssertEqual(ProductMarkup.text(price: 1_500, cost: 600), "+900\(nbsp)₽ · 150%")
        XCTAssertEqual(ProductMarkup.text(price: 1_000, cost: 0), "+1\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(ProductMarkup.text(price: 500, cost: 1_000), "−500\(nbsp)₽ · −50%")
        XCTAssertNil(ProductMarkup.text(price: 1_500, cost: nil))
        XCTAssertNil(ProductMarkup.text(price: 0, cost: 600))
    }

    func testServiceOptionsPutPiercingFirst() {
        let tattoo = Service(id: 1, name: "Мини тату", category: .tattoo, price: 2_000, priceFrom: false, durationMin: 60, aftercareTemplateId: nil, active: true, sort: 0)
        let helix = Service(id: 2, name: "Хеликс", category: .piercing, price: 2_000, priceFrom: false, durationMin: 30, aftercareTemplateId: nil, active: true, sort: 2)
        let lobe = Service(id: 3, name: "Мочка", category: .piercing, price: 1_600, priceFrom: false, durationMin: 30, aftercareTemplateId: nil, active: true, sort: 1)
        let hidden = Service(id: 4, name: "Септум", category: .piercing, price: 2_500, priceFrom: false, durationMin: 30, aftercareTemplateId: nil, active: false, sort: 3)
        let all = [tattoo, helix, lobe, hidden]

        XCTAssertEqual(ProductServiceOptions.options(all, selected: []).map(\.id), [3, 2, 1])
        XCTAssertEqual(ProductServiceOptions.options(all, selected: [4]).map(\.id), [3, 2, 4, 1], "a hidden linked service stays")
        XCTAssertEqual(ProductServiceOptions.names(of: [2, 99, 3], in: all), ["Хеликс", "Мочка"])
    }

    // MARK: - Helpers

    private func encoded(_ body: ProductBody) throws -> [String: Any] {
        let data = try JSONCoding.makeEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
