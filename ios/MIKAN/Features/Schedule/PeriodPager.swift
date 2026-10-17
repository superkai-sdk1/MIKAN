import Observation
import SwiftUI

nonisolated enum PeriodPaging {
    /// ±400 pages: more than a year of days and years of weeks/months.
    static let range = -400...400
    /// Re-base the pager when the user gets this close to either end.
    static let rebaseMargin = 20
}

/// Horizontally paged periods. Page `0` is the base period; pages are created lazily.
///
/// Width comes from the scroll container (keeps `scrollPosition(id:)` landing on the right page).
/// Height comes from the pager's own frame: the scroll container also counts the area under the
/// tab bar, which made pages taller than the visible region and pushed their tops under the header.
struct PeriodPager<Page: View>: View {
    @Binding var offset: Int?
    @ViewBuilder let page: (Int) -> Page

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(PeriodPaging.range, id: \.self) { index in
                        page(index)
                            .containerRelativeFrame(.horizontal)
                            .frame(height: proxy.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $offset)
            .scrollIndicators(.hidden)
        }
    }
}

/// Vertical position shared by all time-grid pages, so paging keeps the same hours in view.
@Observable
final class GridScrollState {
    /// Minute of the day at the top edge of the visible grid.
    var topMinute: Double
    /// Set once the user scrolls vertically; stops automatic positioning.
    var userScrolled = false
    /// Incremented for programmatic scrolls that every page should follow.
    private(set) var request = 0

    init(topMinute: Int = WorkdayHours.standard.startMinute) {
        self.topMinute = Double(topMinute)
    }

    func scroll(toMinute minute: Int, resetsUserScroll: Bool = true) {
        topMinute = Double(minute)
        if resetsUserScroll { userScrolled = false }
        request += 1
    }
}
