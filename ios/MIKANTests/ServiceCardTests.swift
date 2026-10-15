import XCTest
@testable import MIKAN

private let nbsp = "\u{00A0}"

/// Builds a catalog service with sensible defaults.
private func makeService(
    id: Int,
    name: String = "Услуга",
    category: ServiceCategory = .piercing,
    group: String? = nil,
    price: Int = 1_000,
    priceMax: Int? = nil,
    priceFrom: Bool = false,
    description: String? = nil,
    variants: [ServiceVariant] = [],
    sort: Int = 0
) -> Service {
    Service(
        id: id, name: name, category: category, group: group, price: price, priceMax: priceMax,
        priceFrom: priceFrom, durationMin: 30, description: description, variants: variants,
        aftercareTemplateId: nil, active: true, sort: sort
    )
}

// Catalog fixtures.
private let ear = makeService(id: 1, name: "Прокол мочки", group: "Ухо", description: "Lobe", sort: 2)
private let helix = makeService(id: 2, name: "Хеликс", group: "Ухо", sort: 1)
private let nostril = makeService(id: 3, name: "Крыло носа", group: "Лицо", sort: 0)
private let legacy = makeService(id: 4, name: "Снятие украшения", group: nil, sort: 0)
private let tattoo = makeService(id: 5, name: "Мини тату", category: .tattoo, description: "Ёлочка или цветок", sort: 9)
private let catalog = [ear, helix, nostril, legacy, tattoo]

final class ServiceCardTests: XCTestCase {
    // MARK: - Price
    func testModeComesFromStoredFields() {
        XCTAssertEqual(ServicePriceMode(priceMax: nil, priceFrom: false), .fixed)
        XCTAssertEqual(ServicePriceMode(priceMax: nil, priceFrom: true), .from)
        XCTAssertEqual(ServicePriceMode(priceMax: 5_000, priceFrom: true), .range)
        XCTAssertEqual(ServicePriceMode(priceMax: 5_000, priceFrom: false), .range, "a maximum always means a range")
    }

    func testEachModeMapsToApiFields() {
        var draft = ServicePriceDraft(mode: .fixed, amount: 2_500, maximum: 5_000)
        XCTAssertEqual(draft.fields, ServicePriceFields(price: 2_500, priceMax: nil, priceFrom: false))

        draft.mode = .from
        XCTAssertEqual(draft.fields, ServicePriceFields(price: 2_500, priceMax: nil, priceFrom: true))

        draft.mode = .range
        XCTAssertEqual(draft.fields, ServicePriceFields(price: 2_500, priceMax: 5_000, priceFrom: true))
    }

    func testMaximumSurvivesModeSwitching() {
        var draft = ServicePriceDraft(price: 2_000, priceMax: 5_000, priceFrom: true)
        draft.mode = .fixed
        XCTAssertNil(draft.fields.priceMax)
        draft.mode = .range
        XCTAssertEqual(draft.fields.priceMax, 5_000)
    }

    func testNegativeAmountIsSentAsZero() {
        XCTAssertEqual(ServicePriceDraft(mode: .fixed, amount: -10).fields.price, 0)
    }

    func testRangeValidation() {
        XCTAssertEqual(ServicePriceDraft(mode: .range, amount: 2_000, maximum: nil).validationMessage, "Укажите максимальную цену.")
        XCTAssertEqual(ServicePriceDraft(mode: .range, amount: 2_000, maximum: 0).validationMessage, "Укажите максимальную цену.")
        XCTAssertEqual(ServicePriceDraft(mode: .range, amount: 5_000, maximum: 5_000).validationMessage, "Максимум должен быть больше минимума.")
        XCTAssertEqual(ServicePriceDraft(mode: .range, amount: 6_000, maximum: 5_000).validationMessage, "Максимум должен быть больше минимума.")
        XCTAssertTrue(ServicePriceDraft(mode: .range, amount: 2_000, maximum: 5_000).isValid)
        XCTAssertTrue(ServicePriceDraft(mode: .range, amount: 0, maximum: 10_000).isValid, "minimum 0 reads as «до N»")
    }

    func testOtherModesAreAlwaysValid() {
        XCTAssertTrue(ServicePriceDraft(mode: .fixed, amount: 0, maximum: 0).isValid)
        XCTAssertTrue(ServicePriceDraft(mode: .from, amount: 0, maximum: nil).isValid)
    }

    func testPreviewReadsLikeTheCatalog() {
        XCTAssertEqual(ServicePriceDraft(mode: .fixed, amount: 2_500).previewText, "2\(nbsp)500\(nbsp)₽")
        XCTAssertEqual(ServicePriceDraft(mode: .fixed, amount: 0).previewText, "Бесплатно")
        XCTAssertEqual(ServicePriceDraft(mode: .from, amount: 15_000).previewText, "от 15\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(ServicePriceDraft(mode: .range, amount: 2_000, maximum: 5_000).previewText, "от 2\(nbsp)000 до 5\(nbsp)000\(nbsp)₽")
        XCTAssertEqual(ServicePriceDraft(mode: .range, amount: 0, maximum: 10_000).previewText, "до 10\(nbsp)000\(nbsp)₽")
    }

    // MARK: - Variants
    func testRoundTripsVariants() {
        let variants = [
            ServiceVariant(name: "Один", price: 2_500, durationMin: nil),
            ServiceVariant(name: "Два", price: 4_000, durationMin: 60),
        ]
        let drafts = ServiceVariantDrafts.drafts(from: variants, defaultDuration: 45)
        XCTAssertEqual(drafts.map(\.hasDuration), [false, true])
        XCTAssertEqual(drafts.map(\.durationMin), [45, 60], "the toggle-off row starts from the service duration")
        XCTAssertEqual(ServiceVariantDrafts.variants(from: drafts), variants)
    }

    func testTrimsNamesSkipsBlankRowsAndDropsDisabledDuration() {
        var custom = ServiceVariantDraft(name: "  Два ", price: 4_000, durationMin: 90, defaultDuration: 45)
        custom.hasDuration = false
        let drafts = [ServiceVariantDraft(defaultDuration: 45), custom]
        XCTAssertEqual(ServiceVariantDrafts.variants(from: drafts), [ServiceVariant(name: "Два", price: 4_000, durationMin: nil)])
        XCTAssertNil(ServiceVariantDrafts.validationMessage(for: drafts), "an untouched row is not an error")
    }

    func testValidation() {
        let named = ServiceVariantDraft(name: "Один", price: 2_500, defaultDuration: 30)
        let nameless = ServiceVariantDraft(name: " ", price: 2_500, defaultDuration: 30)
        XCTAssertNil(ServiceVariantDrafts.validationMessage(for: [named]))
        XCTAssertEqual(ServiceVariantDrafts.validationMessage(for: [named, nameless]), "Укажите название у каждого варианта.")

        let duplicate = ServiceVariantDraft(name: "один ", price: 3_000, defaultDuration: 30)
        XCTAssertEqual(ServiceVariantDrafts.validationMessage(for: [named, duplicate]), "Названия вариантов не должны повторяться.")

        let long = ServiceVariantDraft(name: String(repeating: "а", count: 101), price: 1, defaultDuration: 30)
        XCTAssertEqual(ServiceVariantDrafts.validationMessage(for: [long]), "Название варианта — не длиннее 100 символов.")

        let many = (1...21).map { ServiceVariantDraft(name: "Вариант \($0)", price: $0, defaultDuration: 30) }
        XCTAssertEqual(ServiceVariantDrafts.validationMessage(for: many), "Не больше 20 вариантов.")
        XCTAssertNil(ServiceVariantDrafts.validationMessage(for: Array(many.prefix(20))))
    }

    func testMovingAndRemovingRows() {
        let rows = ["А", "Б", "В"].map { ServiceVariantDraft(name: $0, defaultDuration: 30) }
        func names(_ drafts: [ServiceVariantDraft]) -> [String] { drafts.map(\.name) }

        XCTAssertEqual(names(ServiceVariantDrafts.moving(rows[2].id, by: -1, in: rows)), ["А", "В", "Б"])
        XCTAssertEqual(names(ServiceVariantDrafts.moving(rows[0].id, by: 1, in: rows)), ["Б", "А", "В"])
        XCTAssertEqual(names(ServiceVariantDrafts.moving(rows[0].id, by: -1, in: rows)), ["А", "Б", "В"], "clamped at the top")
        XCTAssertEqual(names(ServiceVariantDrafts.moving(rows[2].id, by: 5, in: rows)), ["А", "Б", "В"], "clamped at the bottom")
        XCTAssertEqual(names(ServiceVariantDrafts.moving(UUID(), by: 1, in: rows)), ["А", "Б", "В"])
        XCTAssertEqual(names(ServiceVariantDrafts.removing(rows[1].id, from: rows)), ["А", "В"])
        XCTAssertEqual(names(rows), ["А", "Б", "В"], "the input is not mutated")
    }

    // MARK: - Editor draft
    func testNewServiceDefaults() {
        let draft = ServiceEditorDraft(service: nil, nextSort: 7)
        XCTAssertEqual(draft.category, .piercing)
        XCTAssertEqual(draft.durationMin, 60)
        XCTAssertEqual(draft.price.mode, .fixed)
        XCTAssertEqual(draft.sort, 7)
        XCTAssertTrue(draft.active)
        XCTAssertFalse(draft.canSave, "a name is required")
        XCTAssertEqual(draft.validationMessage, "Укажите название услуги.", "a blocked Save always says why")
        XCTAssertEqual(ServiceEditorDraft(service: nil, nextSort: -1).sort, 0)
    }

    func testBodyCarriesEveryField() {
        var service = makeService(
            id: 5, name: "Соски", group: "Тело", price: 2_500, description: "Nipple",
            variants: [ServiceVariant(name: "Два", price: 4_000, durationMin: 60)], sort: 3
        )
        service.imageUrl = "/uploads/cover.jpg"
        service.imagePrompt = "front view"
        service.photos = ["/uploads/a.jpg", "/uploads/b.jpg"]
        service.aftercareTemplateId = 2

        let body = ServiceEditorDraft(service: service, nextSort: 0).body
        XCTAssertEqual(body.name, "Соски")
        XCTAssertEqual(body.category, .piercing)
        XCTAssertEqual(body.group.value, "Тело")
        XCTAssertEqual(body.price, 2_500)
        XCTAssertNil(body.priceMax.value)
        XCTAssertFalse(body.priceFrom)
        XCTAssertEqual(body.durationMin, 30)
        XCTAssertEqual(body.description.value, "Nipple")
        XCTAssertEqual(body.imageUrl.value, "/uploads/cover.jpg")
        XCTAssertEqual(body.imagePrompt.value, "front view")
        XCTAssertEqual(body.photos, ["/uploads/a.jpg", "/uploads/b.jpg"])
        XCTAssertEqual(body.variants, service.variants)
        XCTAssertEqual(body.aftercareTemplateId.value, 2)
        XCTAssertTrue(body.active)
        XCTAssertEqual(body.sort, 3)
    }

    func testBlankOptionalTextIsSentAsNull() throws {
        var draft = ServiceEditorDraft(service: makeService(id: 1, group: "Ухо", description: "Текст"), nextSort: 0)
        draft.name = "  Мочка  "
        draft.group = "   "
        draft.description = "\n"
        draft.imagePrompt = " "
        let body = draft.body
        XCTAssertEqual(body.name, "Мочка")
        XCTAssertNil(body.group.value)
        XCTAssertNil(body.description.value)
        XCTAssertNil(body.imagePrompt.value)

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(body), encoding: .utf8))
        XCTAssertTrue(json.contains(#""group":null"#), "PATCH must clear the field explicitly")
        XCTAssertTrue(json.contains(#""imageUrl":null"#))
    }

    func testRangePriceGoesIntoTheBody() {
        var draft = ServiceEditorDraft(service: nil, nextSort: 0)
        draft.name = "Мини тату"
        draft.price = ServicePriceDraft(mode: .range, amount: 2_000, maximum: 5_000)
        XCTAssertEqual(draft.body.price, 2_000)
        XCTAssertEqual(draft.body.priceMax.value, 5_000)
        XCTAssertTrue(draft.body.priceFrom)
        XCTAssertTrue(draft.canSave)
    }

    func testInvalidPartsBlockSaving() {
        var draft = ServiceEditorDraft(service: makeService(id: 1), nextSort: 0)
        XCTAssertTrue(draft.canSave)

        draft.price = ServicePriceDraft(mode: .range, amount: 5_000, maximum: 1_000)
        XCTAssertEqual(draft.validationMessage, "Максимум должен быть больше минимума.")
        XCTAssertFalse(draft.canSave)

        draft.price = ServicePriceDraft(mode: .fixed, amount: 1_000)
        draft.variants = [ServiceVariantDraft(name: "", price: 500, defaultDuration: 30)]
        XCTAssertFalse(draft.canSave)

        draft.variants = []
        draft.imagePrompt = String(repeating: "x", count: 1_001)
        XCTAssertEqual(draft.validationMessage, "Не длиннее 1000 символов (сейчас 1001).")

        draft.imagePrompt = ""
        draft.photos = (0...12).map { "/uploads/\($0).jpg" }
        XCTAssertEqual(draft.validationMessage, "Не больше 12 фото работ.")

        draft.photos = []
        draft.durationMin = 0
        XCTAssertEqual(draft.validationMessage, "Длительность — от 1 минуты до 24 часов.")
        XCTAssertFalse(draft.canSave)
    }

    func testServiceBodyFromServiceKeepsEverything() {
        var service = makeService(id: 4, name: "Мини тату", category: .tattoo, group: "Тату", price: 2_000, priceMax: 5_000, priceFrom: true)
        service.imagePrompt = "small rose"
        service.photos = ["/uploads/x.jpg"]
        let body = ServiceBody(service)
        XCTAssertEqual(body.name, "Мини тату")
        XCTAssertEqual(body.category, .tattoo)
        XCTAssertEqual(body.priceMax.value, 5_000)
        XCTAssertTrue(body.priceFrom)
        XCTAssertEqual(body.imagePrompt.value, "small rose")
        XCTAssertEqual(body.photos, ["/uploads/x.jpg"])
    }

    func testLimits() {
        XCTAssertEqual(ServiceLimits.remainingPhotos(current: 0), 12)
        XCTAssertEqual(ServiceLimits.remainingPhotos(current: 10), 2)
        XCTAssertEqual(ServiceLimits.remainingPhotos(current: 15), 0)
        XCTAssertNil(ServiceLimits.imagePromptMessage(String(repeating: "x", count: 1_000)))
        XCTAssertNil(ServiceLimits.imagePromptMessage("  short  "))
    }

    // MARK: - Catalog

    func testSortsBySortThenName() {
        let a = makeService(id: 10, name: "Б", sort: 1)
        let b = makeService(id: 11, name: "А", sort: 1)
        let c = makeService(id: 12, name: "В", sort: 0)
        XCTAssertEqual(ServiceCatalog.sorted([a, b, c]).map(\.id), [12, 11, 10])
    }

    func testUpsertReplacesOrInsertsInOrder() {
        var renamed = helix
        renamed.sort = 5
        XCTAssertEqual(ServiceCatalog.upserting(renamed, into: [ear, helix]).map(\.id), [1, 2])
        XCTAssertEqual(ServiceCatalog.upserting(renamed, into: [ear, helix]).last?.sort, 5)
        XCTAssertEqual(ServiceCatalog.upserting(nostril, into: [ear, helix]).map(\.id), [3, 2, 1])
    }

    func testSearchMatchesNameDescriptionAndGroup() {
        XCTAssertEqual(ServiceCatalog.filter(catalog, query: "мочк").map(\.id), [1])
        XCTAssertEqual(ServiceCatalog.filter(catalog, query: "LOBE").map(\.id), [1])
        XCTAssertEqual(ServiceCatalog.filter(catalog, query: "ухо").map(\.id), [1, 2])
        XCTAssertEqual(ServiceCatalog.filter(catalog, query: "елочка").map(\.id), [5], "«е» finds «ё»")
        XCTAssertEqual(ServiceCatalog.filter(catalog, query: "ухо хел").map(\.id), [2], "every word must match")
        XCTAssertEqual(ServiceCatalog.filter(catalog, query: "  ").count, catalog.count)
        XCTAssertTrue(ServiceCatalog.filter(catalog, query: "брови").isEmpty)
    }

    func testSectionsByCategoryThenGroup() {
        let sections = ServiceCatalog.sections(catalog)
        XCTAssertEqual(sections.map(\.category), [.tattoo, .piercing, .piercing, .piercing])
        XCTAssertEqual(sections.map(\.group), [nil, "Лицо", "Ухо", "Другое"], "ungrouped services go last")
        XCTAssertEqual(sections.map(\.isFirstInCategory), [true, true, false, false])
        XCTAssertEqual(sections[2].services.map(\.id), [2, 1], "catalog order inside a group")
        XCTAssertEqual(sections.map(\.id), ["tattoo|", "piercing|Лицо", "piercing|Ухо", "piercing|Другое"])
    }

    func testCategoryWithoutGroupsHasOneUntitledSection() {
        let sections = ServiceCatalog.sections([legacy, makeService(id: 9, name: "Ещё", sort: 1)])
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].group)
        XCTAssertEqual(sections[0].services.map(\.id), [4, 9])
        XCTAssertTrue(ServiceCatalog.sections([]).isEmpty)
    }

    func testGroupSuggestionsPerCategory() {
        let duplicate = makeService(id: 6, name: "Трагус", group: "Ухо", sort: 3)
        let suggestions = ServiceCatalog.groupSuggestions(catalog + [duplicate])
        XCTAssertEqual(suggestions[.piercing], ["Лицо", "Ухо"])
        XCTAssertNil(suggestions[.tattoo], "no named groups — no suggestions")
    }

    func testNextSort() {
        XCTAssertEqual(ServiceCatalog.nextSort(after: catalog), 10)
        XCTAssertEqual(ServiceCatalog.nextSort(after: []), 0)
    }

    func testHistoryPaging() {
        XCTAssertTrue(ServiceHistoryPaging.hasMore(loaded: 50, total: 120, lastPageCount: 50, pageSize: 50))
        XCTAssertFalse(ServiceHistoryPaging.hasMore(loaded: 120, total: 120, lastPageCount: 20, pageSize: 50))
        XCTAssertTrue(ServiceHistoryPaging.hasMore(loaded: 50, total: nil, lastPageCount: 50, pageSize: 50))
        XCTAssertFalse(ServiceHistoryPaging.hasMore(loaded: 70, total: nil, lastPageCount: 20, pageSize: 50))
    }

    func testAppendingPageSkipsKnownItems() {
        XCTAssertEqual(ServiceHistoryPaging.appending([helix, nostril], to: [ear, helix]).map(\.id), [1, 2, 3])
    }

    // MARK: - Fixes from review

    func testOffGridAndLongDurationsCanBeSaved() {
        var short = makeService(id: 1)
        short.durationMin = 10
        XCTAssertTrue(ServiceEditorDraft(service: short, nextSort: 0).canSave, "an existing 10-minute service stays savable")
        short.durationMin = 13 * 60
        XCTAssertTrue(ServiceEditorDraft(service: short, nextSort: 0).canSave, "13 hours is within the server limit")
        short.durationMin = 24 * 60 + 1
        XCTAssertFalse(ServiceEditorDraft(service: short, nextSort: 0).canSave)
    }

    func testDurationSteppingKeepsTheGridAndCustomValues() {
        XCTAssertEqual(ServiceLimits.steppedDuration(60, up: true), 75)
        XCTAssertEqual(ServiceLimits.steppedDuration(60, up: false), 45)
        XCTAssertEqual(ServiceLimits.steppedDuration(50, up: false), 45, "snaps down to the grid")
        XCTAssertEqual(ServiceLimits.steppedDuration(10, up: true), 15, "snaps up to the grid")
        XCTAssertEqual(ServiceLimits.steppedDuration(10, up: false), 10, "a short custom duration is kept")
        XCTAssertEqual(ServiceLimits.steppedDuration(15, up: false), 15, "never below one step")
        XCTAssertEqual(ServiceLimits.steppedDuration(1_435, up: true), 1_440)
        XCTAssertEqual(ServiceLimits.steppedDuration(1_440, up: true), 1_440)
        XCTAssertEqual(ServiceLimits.steppedDuration(2_000, up: false), 1_440, "back into the range")
        XCTAssertFalse(ServiceLimits.canStepDuration(15, up: false))
        XCTAssertFalse(ServiceLimits.canStepDuration(1_440, up: true))
        XCTAssertTrue(ServiceLimits.canStepDuration(13 * 60 + 20, up: true))
        XCTAssertNil(ServiceLimits.durationMessage(1))
        XCTAssertNil(ServiceLimits.durationMessage(1_440))
        XCTAssertNotNil(ServiceLimits.durationMessage(1_441))
    }

    func testFreshVariantRowSeededWithThePriceDoesNotBlockSaving() {
        var draft = ServiceEditorDraft(service: makeService(id: 1, price: 2_500), nextSort: 0)
        var row = ServiceVariantDraft.new(price: 2_500, defaultDuration: 30)
        draft.variants = [row]
        XCTAssertTrue(row.isBlank)
        XCTAssertTrue(draft.canSave)
        XCTAssertTrue(draft.body.variants.isEmpty, "the untouched row is skipped")

        row.price = 3_000
        draft.variants = [row]
        XCTAssertEqual(draft.validationMessage, "Укажите название у каждого варианта.", "a changed price makes it a real row")

        row.name = "Два"
        draft.variants = [row]
        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(draft.body.variants, [ServiceVariant(name: "Два", price: 3_000, durationMin: nil)])
    }

    func testVariantDurationOutsideTheRangeBlocksSaving() {
        var row = ServiceVariantDraft(name: "Один", price: 1_000, durationMin: 0, defaultDuration: 30)
        XCTAssertEqual(ServiceVariantDrafts.validationMessage(for: [row]), "Длительность варианта — от 1 минуты до 24 часов.")
        row.hasDuration = false
        XCTAssertNil(ServiceVariantDrafts.validationMessage(for: [row]), "an unused duration does not matter")
    }

    func testGenerationOutcome() {
        var service = makeService(id: 1)
        XCTAssertFalse(ServiceImageGeneration.hasNewPicture(service, baseline: nil), "still no picture")
        service.imageUrl = "/uploads/new.png"
        XCTAssertTrue(ServiceImageGeneration.hasNewPicture(service, baseline: nil))
        XCTAssertTrue(ServiceImageGeneration.hasNewPicture(service, baseline: "/uploads/old.png"))
        XCTAssertFalse(ServiceImageGeneration.hasNewPicture(service, baseline: "/uploads/new.png"))
        XCTAssertFalse(ServiceImageGeneration.hasNewPicture(nil, baseline: nil))

        let busy = APIError.server(status: 409, code: "conflict", message: "Картинка для этой услуги уже генерируется — подождите пару минут")
        let noKey = APIError.server(status: 409, code: "conflict", message: "Генерация картинок не настроена")
        XCTAssertTrue(ServiceImageGeneration.isAlreadyGenerating(busy))
        XCTAssertFalse(ServiceImageGeneration.isAlreadyGenerating(noKey))
        XCTAssertFalse(ServiceImageGeneration.isAlreadyGenerating(CancellationError()))

        XCTAssertTrue(ServiceImageGeneration.mayStillFinish(APIError.transport(message: "Сервер не отвечает.", outcomeUnknown: true)))
        XCTAssertTrue(ServiceImageGeneration.mayStillFinish(APIError.transport(message: "Ошибка сети.")))
        XCTAssertFalse(ServiceImageGeneration.mayStillFinish(busy))
        XCTAssertFalse(ServiceImageGeneration.mayStillFinish(CancellationError()))
    }
}
