import XCTest
@testable import MIKAN

private typealias F = InventoryFixtures

/// The categories editor: names like the server checks them, drag reordering and the scopes of a section.
final class CategoryEditingTests: XCTestCase {
    private let scope = [
        F.category(1, "Кольца", position: 0, count: 3),
        F.category(2, "Лабрет", position: 1, count: 12),
        F.category(3, "Септум", position: 2),
        F.category(4, "Ёлочки", position: 3),
    ]

    func testNameProblems() {
        XCTAssertEqual(CategoryEditing.nameProblem("  ", in: scope), "Укажите название категории.")
        XCTAssertEqual(CategoryEditing.nameProblem(String(repeating: "а", count: 101), in: scope), "Название — не длиннее 100 символов.")
        XCTAssertEqual(CategoryEditing.nameProblem(" лабрет ", in: scope), "Категория «Лабрет» уже есть.", "case-insensitive, trimmed")
        XCTAssertEqual(CategoryEditing.nameProblem("Елочки", in: scope), "Категория «Ёлочки» уже есть.", "«ё» reads as «е»")
        XCTAssertNil(CategoryEditing.nameProblem("Лабрет", in: scope, excluding: 2), "renaming to its own name in another case")
        XCTAssertNil(CategoryEditing.nameProblem("Дермалы", in: scope))
    }

    func testReorderingRenumbersPositions() {
        let moved = CategoryEditing.reordered(scope, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(moved.map(\.id), [4, 1, 2, 3])
        XCTAssertEqual(moved.map(\.position), [0, 1, 2, 3])

        let down = CategoryEditing.reordered(scope, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(down.map(\.id), [2, 3, 1, 4], "List.onMove offsets: before the old index 3")
    }

    func testReplacingOneScopeKeepsTheOthers() {
        let ear = F.category(10, "Ухо", section: .service, serviceCategory: .piercing, position: 0)
        let face = F.category(11, "Лицо", section: .service, serviceCategory: .piercing, position: 1)
        let tattoo = F.category(12, "Тату", section: .service, serviceCategory: .tattoo, position: 0)
        let all = [ear, face, tattoo]
        let reordered = CategoryEditing.reordered([ear, face], fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let result = CategoryEditing.replacingScope(in: all, section: .service, serviceCategory: .piercing, with: reordered)
        XCTAssertEqual(result.scope(.service, serviceCategory: .piercing).map(\.name), ["Лицо", "Ухо"])
        XCTAssertEqual(result.scope(.service, serviceCategory: .tattoo).map(\.id), [12])

        var renamed = face
        renamed.name = "Лицо и губы"
        XCTAssertEqual(CategoryEditing.upserting(renamed, in: all).map(\.name), ["Ухо", "Лицо и губы", "Тату"])
        XCTAssertEqual(CategoryEditing.upserting(F.category(13, "Тело", position: 0), in: all).map(\.id), [10, 11, 12, 13])
    }

    func testScopesAndCounts() {
        XCTAssertEqual(CategoryEditing.scopes(of: .jewelry), [nil])
        XCTAssertEqual(CategoryEditing.scopes(of: .service), [.tattoo, .piercing, .other])
        XCTAssertEqual(CategoryEditing.countText(0, section: .goods), "Пусто")
        XCTAssertEqual(CategoryEditing.countText(12, section: .jewelry), "12 позиций")
        XCTAssertEqual(CategoryEditing.countText(3, section: .service), "3 услуги")
        XCTAssertEqual(CategoryEditing.countText(21, section: .consumable), "21 позиция")
    }
}
