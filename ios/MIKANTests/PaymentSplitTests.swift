import XCTest
@testable import MIKAN

final class PaymentSplitTests: XCTestCase {
    func testSumRemainingAndBalance() {
        let split = PaymentSplit(cash: 1_500, card: 2_000, transfer: 0)
        XCTAssertEqual(split.sum, 3_500)
        XCTAssertEqual(split.remaining(for: 4_000), 500)
        XCTAssertEqual(split.remaining(for: 3_000), -500, "negative remaining means overpaid")
        XCTAssertTrue(split.isBalanced(for: 3_500))
        XCTAssertFalse(split.isBalanced(for: 4_000))
        XCTAssertEqual(split.payments, Payments(cash: 1_500, card: 2_000, transfer: 0))
    }

    func testNegativeAmountsNeverBalance() {
        let split = PaymentSplit(cash: 4_000, card: -500, transfer: 0)
        XCTAssertEqual(split.sum, 3_500)
        XCTAssertTrue(split.hasNegative)
        XCTAssertFalse(split.isBalanced(for: 3_500))
    }

    func testSubscriptReadsAndWritesEachMethod() {
        var split = PaymentSplit()
        split[.cash] = 100
        split[.card] = 200
        split[.transfer] = 300
        XCTAssertEqual(split, PaymentSplit(cash: 100, card: 200, transfer: 300))
        XCTAssertEqual(PaymentMethod.allCases.map { split[$0] }, [100, 200, 300])
    }

    func testSingleMethodWithoutDepositTakesTheWholeTotal() {
        XCTAssertEqual(PaymentSplit.single(.card, total: 3_500, deposit: 0), PaymentSplit(cash: 0, card: 3_500, transfer: 0))
        XCTAssertEqual(PaymentSplit.single(.cash, total: -10, deposit: 0), PaymentSplit(), "never negative")
        for method in PaymentMethod.allCases {
            XCTAssertTrue(PaymentSplit.single(method, total: 9_999, deposit: 0).isBalanced(for: 9_999))
        }
    }

    func testSingleMethodKeepsDepositInTransfer() {
        let split = PaymentSplit.single(.cash, total: 8_000, deposit: 2_000)
        XCTAssertEqual(split, PaymentSplit(cash: 6_000, card: 0, transfer: 2_000))
        XCTAssertTrue(split.isBalanced(for: 8_000))

        let byTransfer = PaymentSplit.single(.transfer, total: 8_000, deposit: 2_000)
        XCTAssertEqual(byTransfer, PaymentSplit(cash: 0, card: 0, transfer: 8_000))
    }

    func testSingleMethodClampsDepositToTotal() {
        let split = PaymentSplit.single(.card, total: 1_000, deposit: 5_000)
        XCTAssertEqual(split, PaymentSplit(cash: 0, card: 0, transfer: 1_000))
        XCTAssertTrue(split.isBalanced(for: 1_000))
        XCTAssertEqual(CheckoutRules.depositApplied(5_000, total: 1_000), 1_000)
        XCTAssertEqual(CheckoutRules.depositApplied(-100, total: 1_000), 0)
    }

    func testPaymentModeChoicesAndTitles() {
        XCTAssertEqual(PaymentMode.choices, [.single(.cash), .single(.card), .single(.transfer), .split])
        XCTAssertEqual(PaymentMode.choices.map(\.title), ["Наличные", "Карта", "Перевод", "Разделить"])
        XCTAssertEqual(PaymentMode.single(.card).method, .card)
        XCTAssertNil(PaymentMode.split.method)
    }

    func testCheckoutRules() {
        let balanced = PaymentSplit(cash: 3_500, card: 0, transfer: 0)
        XCTAssertTrue(CheckoutRules.canSubmit(lineCount: 2, linesValid: true, subtotal: 4_000, discount: 500, split: balanced))
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 0, linesValid: true, subtotal: 0, discount: 0, split: PaymentSplit()), "empty cart")
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 2, linesValid: false, subtotal: 4_000, discount: 500, split: balanced), "invalid line")
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 4_000, discount: 0, split: balanced), "split ≠ total")
        XCTAssertFalse(CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 400, discount: 500, split: PaymentSplit()), "discount > subtotal")
        XCTAssertTrue(CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 500, discount: 500, split: PaymentSplit()), "free sale with full discount")
        XCTAssertEqual(CheckoutRules.total(subtotal: 4_000, discount: 500), 3_500)
        XCTAssertEqual(CheckoutRules.total(subtotal: 400, discount: 500), 0)
    }
}

final class CashTenderTests: XCTestCase {
    func testChangeIsShownOnlyWhenEnoughIsReceived() {
        XCTAssertNil(CashTender.change(received: nil, due: 4_500), "empty field")
        XCTAssertNil(CashTender.change(received: 4_000, due: 4_500), "short")
        XCTAssertEqual(CashTender.change(received: 4_500, due: 4_500), 0)
        XCTAssertEqual(CashTender.change(received: 5_000, due: 4_500), 500)
    }

    func testEmptyFieldDoesNotBlockButAShortAmountDoes() {
        XCTAssertTrue(CashTender.isEnough(received: nil, due: 4_500))
        XCTAssertTrue(CashTender.isEnough(received: 4_500, due: 4_500))
        XCTAssertFalse(CashTender.isEnough(received: 0, due: 4_500))
        XCTAssertFalse(CashTender.isEnough(received: 4_499, due: 4_500))
    }

    func testSuggestionsStartWithTheExactAmountAndRoundUpToBanknotes() {
        XCTAssertEqual(CashTender.suggestions(for: 4_300), [4_300, 4_500, 5_000])
        XCTAssertEqual(CashTender.suggestions(for: 1_200), [1_200, 1_500, 2_000, 5_000])
        XCTAssertEqual(CashTender.suggestions(for: 5_000), [5_000])
        XCTAssertEqual(CashTender.suggestions(for: 0), [])
    }
}
