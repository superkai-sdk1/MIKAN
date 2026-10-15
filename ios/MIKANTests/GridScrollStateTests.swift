import XCTest
@testable import MIKAN

/// Initial vertical position of the time grid and the hour height per calendar scale.
@MainActor
final class GridScrollStateTests: XCTestCase {
    func testWeekUsesCompactHourHeightAndOtherScalesTheRegularOne() {
        XCTAssertEqual(TimeGridPage.hourHeight(for: .week), 48)
        XCTAssertEqual(TimeGridPage.hourHeight(for: .day), 60)
        XCTAssertEqual(TimeGridPage.hourHeight(for: .threeDays), 60)
    }

    func testStateStartsAtTheSeededMinuteWithoutPendingRequests() {
        let state = GridScrollState(topMinute: 15 * 60)

        XCTAssertEqual(state.topMinute, 900)
        XCTAssertFalse(state.userScrolled)
        XCTAssertEqual(state.request, 0)
    }

    func testProgrammaticScrollResetsUserScrollAndIssuesARequest() {
        let state = GridScrollState()
        state.userScrolled = true

        state.scroll(toMinute: 10 * 60)

        XCTAssertEqual(state.topMinute, 600)
        XCTAssertFalse(state.userScrolled)
        XCTAssertEqual(state.request, 1)
    }
}
