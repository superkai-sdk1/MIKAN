import XCTest
@testable import MIKAN

/// «+ Услуга» picker: popular ranking and search over all services.
final class ServicePickingTests: XCTestCase {
    private func service(_ id: Int, _ name: String, _ category: ServiceCategory = .piercing, sort: Int = 0, active: Bool = true) -> Service {
        Service(id: id, name: name, category: category, price: 2500, priceFrom: false, durationMin: 30,
                description: nil, aftercareTemplateId: nil, active: active, sort: sort)
    }

    private func top(_ id: Int?, _ quantity: Int) -> TopService {
        TopService(serviceId: id, name: "x", quantity: quantity, revenue: 0)
    }

    private lazy var catalog = [
        service(1, "Прокол мочки", sort: 1),
        service(2, "Прокол хеликса", sort: 2),
        service(3, "Тату мини", .tattoo, sort: 3),
        service(4, "Снятие украшения", .other, sort: 4),
        service(5, "Старая услуга", sort: 0, active: false),
    ]

    func testPopularPutsBestSellersFirstAndFillsTheRestInCatalogOrder() {
        let result = ServicePicking.popular(services: catalog, top: [top(3, 2), top(2, 9)], limit: 4)

        XCTAssertEqual(result.map(\.id), [2, 3, 1, 4])
    }

    func testPopularSkipsInactiveUnknownAndCustomServices() {
        let result = ServicePicking.popular(services: catalog, top: [top(5, 50), top(nil, 40), top(99, 30)], limit: 2)

        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testPopularWithoutSalesIsTheCatalogOrder() {
        XCTAssertEqual(ServicePicking.popular(services: catalog, top: [], limit: 6).map(\.id), [1, 2, 3, 4])
    }

    func testSearchIgnoresCaseYoAndMatchesEveryWord() {
        XCTAssertEqual(ServicePicking.search(catalog, query: "ПРОКОЛ").map(\.id), [1, 2])
        XCTAssertEqual(ServicePicking.search(catalog, query: "прокол хел").map(\.id), [2])
        XCTAssertEqual(ServicePicking.search([service(7, "Чёрная краска")], query: "черная").map(\.id), [7])
    }

    func testSearchMatchesTheCategoryTitleAndHidesInactiveServices() {
        let tattoo = ServicePicking.search(catalog, query: ServiceCategory.tattoo.title)

        XCTAssertEqual(tattoo.map(\.id), [3])
        XCTAssertTrue(ServicePicking.search(catalog, query: "Старая").isEmpty)
        XCTAssertTrue(ServicePicking.search(catalog, query: "   ").isEmpty)
    }
}
