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
        split[.qr] = 400
        XCTAssertEqual(split, PaymentSplit(cash: 100, card: 200, transfer: 300, qr: 400))
        XCTAssertEqual(PaymentMethod.allCases.map { split[$0] }, [100, 200, 300, 400])
        XCTAssertEqual(split.sum, 1_000)
        XCTAssertEqual(split.payments, Payments(cash: 100, card: 200, transfer: 300, qr: 400))
        XCTAssertEqual(PaymentSplit(split.payments), split)
    }

    func testQrTakesOnlyTheAmountDueNeverThePrepayment() {
        let split = PaymentSplit.single(.qr, total: 8_000, deposit: 2_000)
        XCTAssertEqual(split, PaymentSplit(qr: 6_000))
        XCTAssertTrue(split.isBalanced(for: 6_000))
        XCTAssertFalse(split.isBalanced(for: 8_000))
        XCTAssertEqual(split.payments(deposit: 2_000), Payments(cash: 0, card: 0, transfer: 0, qr: 6_000, deposit: 2_000))
        XCTAssertEqual(split.payments(deposit: 2_000).total, 8_000)
        XCTAssertTrue(PaymentSplit(qr: -1).hasNegative)
        XCTAssertEqual(PaymentMethod.qr.instrumentalTitle, "По QR")
        XCTAssertEqual(PaymentMethod.cash.instrumentalTitle, "Наличными")
    }

    func testSingleMethodWithoutDepositTakesTheWholeTotal() {
        XCTAssertEqual(PaymentSplit.single(.card, total: 3_500, deposit: 0), PaymentSplit(cash: 0, card: 3_500, transfer: 0))
        XCTAssertEqual(PaymentSplit.single(.cash, total: -10, deposit: 0), PaymentSplit(), "never negative")
        for method in PaymentMethod.allCases {
            XCTAssertTrue(PaymentSplit.single(method, total: 9_999, deposit: 0).isBalanced(for: 9_999))
        }
    }

    func testSingleMethodPaysTheAmountDueAndReservesNothingInTransfer() {
        let split = PaymentSplit.single(.cash, total: 8_000, deposit: 2_000)
        XCTAssertEqual(split, PaymentSplit(cash: 6_000))
        XCTAssertTrue(split.isBalanced(for: 6_000))

        let byTransfer = PaymentSplit.single(.transfer, total: 8_000, deposit: 2_000)
        XCTAssertEqual(byTransfer, PaymentSplit(transfer: 6_000), "the prepayment is not a transfer")
    }

    func testPrepaymentLargerThanTheTotalLeavesNothingDueAndARemainder() {
        let split = PaymentSplit.single(.cash, total: 1_000, deposit: 5_000)
        XCTAssertEqual(split, PaymentSplit())
        XCTAssertTrue(split.isBalanced(for: 0))
        XCTAssertEqual(CheckoutRules.depositApplied(5_000, total: 1_000), 1_000)
        XCTAssertEqual(CheckoutRules.amountDue(total: 1_000, deposit: 5_000), 0)
        XCTAssertEqual(CheckoutRules.depositRemainder(5_000, total: 1_000), 4_000, "stays held for the appointment")
    }

    func testDepositRulesNeverGoNegative() {
        XCTAssertEqual(CheckoutRules.depositApplied(-100, total: 1_000), 0)
        XCTAssertEqual(CheckoutRules.amountDue(total: 1_000, deposit: -100), 1_000)
        XCTAssertEqual(CheckoutRules.depositRemainder(-100, total: 1_000), 0)
        XCTAssertEqual(CheckoutRules.amountDue(total: 8_000, deposit: 2_000), 6_000)
        XCTAssertEqual(CheckoutRules.depositRemainder(2_000, total: 8_000), 0)
        XCTAssertEqual(CheckoutRules.depositApplied(2_000, total: -10), 0)
    }

    func testPaymentsWithoutPrepaymentSendAZeroDeposit() {
        let split = PaymentSplit(cash: 1_000, transfer: 500)
        XCTAssertEqual(split.payments, Payments(cash: 1_000, card: 0, transfer: 500, qr: 0, deposit: 0))
        XCTAssertEqual(split.payments(deposit: -5).deposit, 0, "never negative")
    }

    func testPaymentModeChoicesAndTitles() {
        let withQr = PaymentMode.choices(qrEnabled: true)
        XCTAssertEqual(withQr, [.single(.cash), .single(.transfer), .single(.qr), .split], "card is no longer taken")
        XCTAssertEqual(withQr.map(\.title), ["Наличные", "Перевод", "QR СБП", "Разделить"])
        XCTAssertEqual(PaymentMode.choices(qrEnabled: false), [.single(.cash), .single(.transfer), .split])
        XCTAssertEqual(PaymentMode.single(.qr).method, .qr)
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

    func testCheckoutRulesBalanceTheMethodsAgainstTheAmountDue() {
        let due = PaymentSplit(cash: 6_000)
        XCTAssertTrue(CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 8_000, discount: 0, deposit: 2_000, split: due))
        XCTAssertFalse(
            CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 8_000, discount: 0, deposit: 2_000, split: PaymentSplit(cash: 8_000)),
            "the prepayment would be paid twice"
        )
        XCTAssertTrue(
            CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 3_000, discount: 0, deposit: 5_000, split: PaymentSplit()),
            "covered by the prepayment"
        )
        XCTAssertTrue(
            CheckoutRules.canSubmit(lineCount: 1, linesValid: true, subtotal: 8_000, discount: 2_000, deposit: 2_000, split: PaymentSplit(qr: 4_000))
        )
    }
}

final class PaymentLinesTests: XCTestCase {
    func testLinesListNonZeroMethodsThenThePrepayment() {
        let payments = Payments(cash: 1_500, card: 0, transfer: 500, qr: 0, deposit: 2_000)
        XCTAssertEqual(payments.paymentLines.map(\.source), [.method(.cash), .method(.transfer), .deposit])
        XCTAssertEqual(payments.paymentLines.map(\.amount), [1_500, 500, 2_000])
        XCTAssertEqual(payments.paymentLines.map(\.title), ["Наличные", "Перевод", "Предоплата"])
        XCTAssertEqual(payments.paymentLines.last?.symbol, PaymentLine.depositSymbol)
        XCTAssertTrue(Payments(cash: 0, card: 0, transfer: 0).paymentLines.isEmpty)
    }

    func testMethodsSummaryIncludesThePrepayment() {
        XCTAssertEqual(PaymentText.methods(Payments(cash: 1_500, card: 0, transfer: 0, deposit: 2_000)), "наличными и предоплатой")
        XCTAssertEqual(
            PaymentText.methods(Payments(cash: 1_000, card: 0, transfer: 500, qr: 0, deposit: 2_000)),
            "наличными, переводом и предоплатой"
        )
        XCTAssertEqual(PaymentText.methods(Payments(cash: 0, card: 0, transfer: 0, deposit: 3_000)), "предоплатой")
        XCTAssertEqual(PaymentText.methods(Payments(cash: 0, card: 0, transfer: 0, qr: 900)), "по QR СБП")
        XCTAssertNil(PaymentText.methods(Payments(cash: 0, card: 0, transfer: 0)))
    }

    func testBreakdownListsNonZeroMethodsWithAmounts() {
        XCTAssertEqual(
            PaymentText.breakdown(PaymentSplit(cash: 1_000, transfer: 2_000)),
            "наличными \(Money.format(1_000)) · переводом \(Money.format(2_000))"
        )
        XCTAssertEqual(PaymentText.breakdown(PaymentSplit(qr: 500)), "по QR СБП \(Money.format(500))")
        XCTAssertNil(PaymentText.breakdown(PaymentSplit()))
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

final class SaleRefundTextTests: XCTestCase {
    func testPrepaymentPartGoesBackToTheAppointment() {
        let payments = Payments(cash: 1_500, card: 0, transfer: 0, qr: 0, deposit: 2_000)

        XCTAssertEqual(SaleRefundText.confirmButton(payments), "Вернуть \(Money.format(1_500))", "only what was paid now")
        let note = "Предоплата \(Money.format(2_000)) вернётся на запись — её можно будет вернуть клиенту или зачесть в новом чеке."
        XCTAssertEqual(SaleRefundText.depositNote(payments), note)
        XCTAssertEqual(
            SaleRefundText.confirmationMessage(payments),
            "Продажа будет отмечена как возвращённая. Это действие нельзя отменить. "
                + "Выдайте клиенту \(Money.format(1_500)) наличными из кассы. \(note)"
        )
    }

    func testSaleWithoutPrepayment() {
        let payments = Payments(cash: 0, card: 0, transfer: 3_000)
        XCTAssertEqual(SaleRefundText.confirmButton(payments), "Вернуть \(Money.format(3_000))")
        XCTAssertNil(SaleRefundText.depositNote(payments))
        XCTAssertEqual(SaleRefundText.confirmationMessage(payments), "Продажа будет отмечена как возвращённая. Это действие нельзя отменить.")
    }

    func testSalePaidEntirelyByPrepayment() {
        let payments = Payments(cash: 0, card: 0, transfer: 0, qr: 0, deposit: 3_000)
        XCTAssertEqual(SaleRefundText.confirmButton(payments), "Оформить возврат")
    }
}
