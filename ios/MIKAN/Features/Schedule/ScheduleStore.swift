import Foundation
import Observation

/// Appointments for one visible range, optionally filtered by master.
nonisolated struct ScheduleQuery: Hashable, Sendable {
    let start: Date
    let end: Date
    let masterId: Int?

    init(period: CalendarPeriod, masterId: Int?) {
        self.start = period.visibleStart
        self.end = period.visibleEnd
        self.masterId = masterId
    }

    func includes(_ appointment: Appointment) -> Bool {
        appointment.startsAt < end && appointment.endsAt > start
            && (masterId == nil || appointment.master.id == masterId)
    }
}

/// Calendar data: a small in-memory cache per visible range, prefetch of neighbours,
/// cancellation of stale requests while paging fast.
@Observable
final class ScheduleStore {
    private static let cacheLimit = 24
    /// Cached ranges older than this are refetched (in the background) when shown again.
    private static let staleAfter: TimeInterval = 30

    private let api: APIClient
    private(set) var cache: [ScheduleQuery: [Appointment]] = [:]
    private(set) var loading: Set<ScheduleQuery> = []
    private(set) var errors: [ScheduleQuery: String] = [:]
    private(set) var visibleQuery: ScheduleQuery?
    /// Master filter for «Все записи».
    var masterFilter: Int?

    @ObservationIgnored private var tasks: [ScheduleQuery: (token: UUID, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var lastUsed: [ScheduleQuery: Date] = [:]
    @ObservationIgnored private var fetchedAt: [ScheduleQuery: Date] = [:]

    init(api: APIClient) {
        self.api = api
    }

    func appointments(for query: ScheduleQuery) -> [Appointment]? { cache[query] }
    func isLoading(_ query: ScheduleQuery) -> Bool { loading.contains(query) }
    func error(for query: ScheduleQuery) -> String? { errors[query] }

    /// Shows `visible`, prefetches `neighbours`, cancels every other request in flight.
    /// With `refresh`, the visible range is reloaded even if cached (cached data stays on screen).
    func focus(on visible: ScheduleQuery, prefetch neighbours: [ScheduleQuery], refresh: Bool = false) {
        visibleQuery = visible
        lastUsed[visible] = .now
        let wanted = Set([visible] + neighbours)
        for (query, entry) in tasks where !wanted.contains(query) {
            entry.task.cancel()
            tasks[query] = nil
            loading.remove(query)
        }
        start(visible, force: refresh || isStale(visible))
        neighbours.forEach { start($0, force: isStale($0)) }
    }

    /// Reloads a range and waits for it (pull-to-refresh).
    func reload(_ query: ScheduleQuery) async {
        let task = start(query, force: true)
        await task?.value
    }

    func refreshVisible() async {
        guard let visibleQuery else { return }
        await reload(visibleQuery)
    }

    /// Applies a created/edited appointment to every cached range (moving it out of ranges it left).
    func upsert(_ appointment: Appointment) {
        for (query, items) in cache {
            let others = items.filter { $0.id != appointment.id }
            cache[query] = query.includes(appointment)
                ? (others + [appointment]).sorted { $0.startsAt < $1.startsAt }
                : others
        }
    }

    private func isStale(_ query: ScheduleQuery) -> Bool {
        guard cache[query] != nil, tasks[query] == nil else { return false }
        return Date.now.timeIntervalSince(fetchedAt[query] ?? .distantPast) > Self.staleAfter
    }

    func reset() {
        tasks.values.forEach { $0.task.cancel() }
        tasks = [:]
        cache = [:]
        loading = []
        errors = [:]
        lastUsed = [:]
        fetchedAt = [:]
        visibleQuery = nil
        masterFilter = nil
    }

    // MARK: - Loading

    @discardableResult
    private func start(_ query: ScheduleQuery, force: Bool) -> Task<Void, Never>? {
        if let running = tasks[query] {
            guard force else { return running.task }
            running.task.cancel()
        } else if !force, cache[query] != nil {
            return nil
        }
        let token = UUID()
        loading.insert(query)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch(query, token: token)
        }
        tasks[query] = (token, task)
        return task
    }

    private func fetch(_ query: ScheduleQuery, token: UUID) async {
        do {
            let items = try await api.appointments(from: query.start, to: query.end, masterId: query.masterId)
            if tasks[query]?.token == token || tasks[query] == nil {
                cache[query] = items
                errors[query] = nil
                lastUsed[query] = .now
                fetchedAt[query] = .now
                trimCache()
            }
        } catch is CancellationError {
            // Superseded by paging or a newer refresh.
        } catch {
            if tasks[query]?.token == token { errors[query] = error.userMessage }
        }
        if tasks[query]?.token == token {
            tasks[query] = nil
            loading.remove(query)
        }
    }

    private func trimCache() {
        guard cache.count > Self.cacheLimit else { return }
        let removable = cache.keys
            .filter { $0 != visibleQuery }
            .sorted { (lastUsed[$0] ?? .distantPast) < (lastUsed[$1] ?? .distantPast) }
            .prefix(cache.count - Self.cacheLimit)
        for query in removable {
            cache[query] = nil
            lastUsed[query] = nil
            fetchedAt[query] = nil
            errors[query] = nil
        }
    }
}
