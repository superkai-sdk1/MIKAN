import XCTest
@testable import MIKAN

final class IdempotencyTests: XCTestCase {
    private let deposit = CashOperationBody(type: .deposit, amount: 500, reason: "Размен")

    func testSameBodyKeepsTheKeyAcrossRetries() {
        var actionKey = IdempotencyKey()
        let first = actionKey.key(for: deposit)
        XCTAssertEqual(actionKey.key(for: CashOperationBody(type: .deposit, amount: 500, reason: "Размен")), first)
    }

    func testChangedBodyIsANewAction() {
        var actionKey = IdempotencyKey()
        let first = actionKey.key(for: deposit)
        let edited = actionKey.key(for: CashOperationBody(type: .deposit, amount: 700, reason: "Размен"))
        XCTAssertNotEqual(edited, first)
        XCTAssertEqual(actionKey.key(for: CashOperationBody(type: .deposit, amount: 700, reason: "Размен")), edited)
    }

    func testResetStartsANewActionEvenForTheSameBody() {
        var actionKey = IdempotencyKey()
        let first = actionKey.key(for: deposit)
        actionKey.reset()
        XCTAssertNotEqual(actionKey.key(for: deposit), first)
    }

    @MainActor
    func testClearingTheCartGivesTheNextIdenticalSaleANewKey() {
        let cart = CartStore()
        cart.addCustomService(name: "Прокол мочки", price: 2500)
        cart.applyOneTap(.cash)
        let body = cart.makeSaleBody()
        let key = cart.saleIdempotencyKey(for: body)
        XCTAssertEqual(cart.saleIdempotencyKey(for: cart.makeSaleBody()), key, "a retry of the same checkout reuses the key")

        cart.clear()
        cart.addCustomService(name: "Прокол мочки", price: 2500)
        cart.applyOneTap(.cash)
        XCTAssertNotEqual(cart.saleIdempotencyKey(for: cart.makeSaleBody()), key, "a new sale must not replay the previous one")
    }

    @MainActor
    func testRequestCarriesTheHeaderOnlyWhenAKeyIsGiven() throws {
        let api = APIClient(serverURL: URL(string: "https://studio.example.ru")!, token: "token")
        let key = UUID()
        let keyed = try api.makeRequest(.post, "sales", query: [], body: Data("{}".utf8), contentType: "application/json", timeout: 20, idempotencyKey: key)
        XCTAssertEqual(keyed.value(forHTTPHeaderField: "Idempotency-Key"), key.uuidString)
        XCTAssertEqual(keyed.url?.absoluteString, "https://studio.example.ru/api/sales")

        let plain = try api.makeRequest(.post, "sales", query: [], body: Data("{}".utf8), contentType: "application/json", timeout: 20)
        XCTAssertNil(plain.value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testClientChatResponseDecodes() throws {
        let none = try Fixtures.decode(ClientChatResponse.self, #"{ "chat": null }"#)
        XCTAssertNil(none.chat)
        let linked = try Fixtures.decode(ClientChatResponse.self, #"{ "chat": \#(Fixtures.botChat) }"#)
        XCTAssertEqual(linked.chat?.chatId, 123_456_789)
    }
}
