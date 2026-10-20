import Foundation
import Testing
@testable import MIKAN

/// «Цены у мастеров» in the service editor (docs/API.md «Service» `masterPrices`).
@MainActor
struct ServiceMasterPricesTests {
    private static func service(
        price: Int = 2_500,
        priceMax: Int? = nil,
        priceFrom: Bool = false,
        variants: [ServiceVariant] = [],
        masterPrices: [ServiceMasterPrice] = []
    ) -> Service {
        Service(
            id: 5, name: "Соски", category: .piercing, group: "Тело", price: price, priceMax: priceMax,
            priceFrom: priceFrom, durationMin: 45, variants: variants, masterPrices: masterPrices,
            aftercareTemplateId: nil, active: true, sort: 0
        )
    }

    private static let pairs = [
        ServiceVariant(name: "Один", price: 2_500, durationMin: nil),
        ServiceVariant(name: "Два", price: 4_000, durationMin: 60),
    ]

    private static func json(_ body: ServiceBody) throws -> [String: Any] {
        let data = try JSONCoding.makeEncoder().encode(body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Loading

    @Test("Saved values equal to the catalog read as empty; variant prices are matched by name")
    func loadReadsCatalogValuesAsEmpty() throws {
        let saved = [
            ServiceMasterPrice(employeeId: 2, price: 3_000, priceMax: nil, variants: [ServiceMasterVariantPrice(name: "Два", price: 5_000)]),
            ServiceMasterPrice(employeeId: 3, price: 2_500, priceMax: nil, variants: [ServiceMasterVariantPrice(name: "Один", price: 2_500)]),
        ]
        let draft = ServiceEditorDraft(service: Self.service(variants: Self.pairs, masterPrices: saved), nextSort: 0)

        #expect(draft.masterPrices.entries.map(\.employeeId) == [2], "an entry equal to the catalog is not an own price")
        let amina = draft.masterPrices.entry(for: 2)
        #expect(amina.price == 3_000)
        let two = try #require(draft.variants.first { $0.name == "Два" })
        #expect(amina.variantPrices == [two.id: 5_000])
        #expect(draft.masterPrices.entry(for: 3).isBlank)
    }

    // MARK: - Body

    @Test("A new card and an untouched one send no own prices; an empty field takes the catalog value")
    func bodyFillsCatalogValues() {
        #expect(ServiceEditorDraft(service: nil, nextSort: 0).body.masterPrices == [])

        var draft = ServiceEditorDraft(service: Self.service(price: 2_000, priceMax: 5_000, priceFrom: true), nextSort: 0)
        #expect(draft.body.masterPrices == [])

        draft.masterPrices.set(ServiceMasterPriceDraft(employeeId: 2, price: 3_000))
        draft.masterPrices.set(ServiceMasterPriceDraft(employeeId: 4, priceMax: 7_000))
        #expect(draft.body.masterPrices == [
            ServiceMasterPrice(employeeId: 2, price: 3_000, priceMax: 5_000),
            ServiceMasterPrice(employeeId: 4, price: 2_000, priceMax: 7_000),
        ])
    }

    @Test("Clearing every field removes the master's entry; editing keeps its place")
    func setRemovesBlankEntries() {
        var prices = ServiceMasterPricesDraft()
        prices.set(ServiceMasterPriceDraft(employeeId: 2, price: 3_000))
        prices.set(ServiceMasterPriceDraft(employeeId: 3, price: 3_500))
        prices.set(ServiceMasterPriceDraft(employeeId: 2, price: 3_200))
        #expect(prices.entries.map(\.employeeId) == [2, 3])
        #expect(prices.entry(for: 2).price == 3_200)

        prices.set(ServiceMasterPriceDraft(employeeId: 2))
        #expect(prices.entries.map(\.employeeId) == [3])
        prices.set(ServiceMasterPriceDraft(employeeId: 9))
        #expect(prices.entries.map(\.employeeId) == [3], "a blank entry is never added")
    }

    @Test("A renamed variant keeps the master's price under the new name; a removed or blank one drops it")
    func variantRenameAndRemoval() throws {
        let saved = [ServiceMasterPrice(
            employeeId: 2, price: 2_500, priceMax: nil,
            variants: [ServiceMasterVariantPrice(name: "Один", price: 2_800), ServiceMasterVariantPrice(name: "Два", price: 5_000)]
        )]
        var draft = ServiceEditorDraft(service: Self.service(variants: Self.pairs, masterPrices: saved), nextSort: 0)
        let one = try #require(draft.variants.first { $0.name == "Один" })
        let two = try #require(draft.variants.first { $0.name == "Два" })

        draft.variants = ServiceVariantDrafts.removing(one.id, from: draft.variants)
        draft.variants = draft.variants.map { row in
            var row = row
            if row.id == two.id { row.name = "  Пара " }
            return row
        }
        let blank = ServiceVariantDraft.new(price: 2_500, defaultDuration: 45)
        draft.variants.append(blank)
        var amina = draft.masterPrices.entry(for: 2)
        amina.variantPrices[blank.id] = 9_000
        draft.masterPrices.set(amina)

        #expect(draft.body.masterPrices == [ServiceMasterPrice(
            employeeId: 2, price: 2_500, priceMax: nil, variants: [ServiceMasterVariantPrice(name: "Пара", price: 5_000)]
        )])
    }

    @Test("Prices of employees who are not masters now go back unchanged")
    func retiredEntriesAreKept() {
        let saved = [ServiceMasterPrice(employeeId: 99, price: 4_000, priceMax: nil)]
        let draft = ServiceEditorDraft(service: Self.service(masterPrices: saved), nextSort: 0)
        #expect(draft.body.masterPrices == saved)
    }

    // MARK: - Validation

    @Test("A master's maximum must be above their minimum, the catalog maximum included")
    func rangeValidation() {
        var draft = ServiceEditorDraft(service: Self.service(price: 2_000, priceMax: 5_000, priceFrom: true), nextSort: 0)
        draft.masterPrices.set(ServiceMasterPriceDraft(employeeId: 2, price: 6_000))
        let catalog = draft.price.fields

        #expect(ServiceMasterPricesDraft.rangeMessage(draft.masterPrices.entry(for: 2), catalog: catalog) == "Максимум должен быть больше минимума.")
        #expect(draft.masterPrices.invalidEntry(catalog: catalog)?.employeeId == 2)
        #expect(draft.validationMessage == "У мастера максимум должен быть больше минимума.")
        #expect(!draft.canSave)

        draft.masterPrices.set(ServiceMasterPriceDraft(employeeId: 2, price: 6_000, priceMax: 8_000))
        #expect(draft.masterPricesMessage == nil)
        #expect(draft.canSave)
    }

    @Test("Own prices are limited to 20 masters")
    func entryLimit() {
        var draft = ServiceEditorDraft(service: Self.service(), nextSort: 0)
        for id in 1...21 {
            draft.masterPrices.set(ServiceMasterPriceDraft(employeeId: id, price: 3_000))
        }
        #expect(draft.validationMessage == "Свои цены — не больше чем у 20 мастеров.")
    }

    // MARK: - Other bodies

    @Test("A body built from a saved service leaves the masters' prices out")
    func fullBodyLeavesMasterPricesOut() throws {
        let service = Self.service(masterPrices: [ServiceMasterPrice(employeeId: 2, price: 3_000, priceMax: nil)])
        #expect(ServiceBody(service).masterPrices == nil)
        #expect(try Self.json(ServiceBody(service))["masterPrices"] == nil)

        let fromEditor = try Self.json(ServiceEditorDraft(service: service, nextSort: 0).body)
        let sent = try #require(fromEditor["masterPrices"] as? [[String: Any]])
        #expect(sent.first?["employeeId"] as? Int == 2)
        #expect(sent.first?["price"] as? Int == 3_000)
    }

    // MARK: - Texts

    @Test("Master price texts: «от» stays the service's, a maximum makes a range")
    func texts() {
        let nbsp = "\u{00A0}"
        #expect(ServiceMasterPriceText.price(ServiceMasterPrice(employeeId: 2, price: 3_000, priceMax: nil), priceFrom: true) == "от 3\(nbsp)000\(nbsp)₽")
        #expect(ServiceMasterPriceText.price(ServiceMasterPrice(employeeId: 2, price: 3_000, priceMax: 6_000), priceFrom: false) == "от 3\(nbsp)000 до 6\(nbsp)000\(nbsp)₽")
        #expect(ServiceMasterPriceText.placeholder(2_500) == "2\(nbsp)500")
        #expect(ServiceMasterPriceText.placeholder(nil) == "—")
        #expect(ServiceMasterPriceText.variants([]) == nil)
    }
}
