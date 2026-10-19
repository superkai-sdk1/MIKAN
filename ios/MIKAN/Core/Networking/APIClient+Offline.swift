import Foundation

// MARK: - Reads that work offline (docs/API.md «Offline mode (app)»)
// Release builds: the Swift 6 optimizer (Xcode 26) generates an invalid module for these generic async helpers
// («Instruction does not dominate all uses» in LLVM verify), so they are compiled without optimization.

extension APIClient {
    /// The server's answer while online; the phone's copy while offline — at once when the app already knows it is
    /// offline, or after a request that could not reach the server. Other failures are thrown as they are.
    @_optimize(none)
    func withOfflineCopy<T: Sendable>(
        _ fetch: () async throws -> T,
        saved: () async -> T?
    ) async throws -> T {
        if connectivity?.isOnline == false, let copy = await saved() { return copy }
        do {
            return try await fetch()
        } catch {
            guard connectivity?.isOnline == false, let copy = await saved() else { throw error }
            return copy
        }
    }

    /// A GET whose answer is saved on the phone after every success and served from there while offline.
    @_optimize(none)
    func cachedGet<T: Codable & Sendable>(_ dataset: OfflineDataset, _ fetch: () async throws -> T) async throws -> T {
        guard let offlineCache else { return try await fetch() }
        return try await withOfflineCopy {
            let value = try await fetch()
            let loadedAt = Date.now
            Task { await offlineCache.save(value, as: dataset, at: loadedAt) }
            return value
        } saved: {
            await offlineCache.load(T.self, dataset)?.payload
        }
    }

    // MARK: Clients

    /// The client list: active clients are saved page by page and, offline, searched on the phone.
    @_optimize(none)
    func clients(search: String = "", archived: Bool = false, limit: Int = 50, offset: Int = 0) async throws -> ItemsResponse<Client> {
        guard let offlineCache, !archived else {
            return try await fetchClients(search: search, archived: archived, limit: limit, offset: offset)
        }
        return try await withOfflineCopy {
            let page = try await fetchClients(search: search, archived: false, limit: limit, offset: offset)
            if search.trimmed.isEmpty {
                let items = page.items
                let total = page.total ?? offset + items.count
                let loadedAt = Date.now
                Task {
                    await offlineCache.update(ClientsSnapshot.self, .clients, at: loadedAt) { saved in
                        ClientsSnapshot.saving(items, offset: offset, total: total, into: saved)
                    }
                }
            }
            return page
        } saved: {
            await offlineCache.load(ClientsSnapshot.self, .clients)?.payload.page(search: search, limit: limit, offset: offset)
        }
    }

    /// The saved active clients, shown by the list at once while the server is asked.
    @_optimize(none)
    func savedClients() async -> ClientsSnapshot? {
        await offlineCache?.load(ClientsSnapshot.self, .clients)?.payload
    }

    // MARK: Appointments

    /// One appointment; offline, its copy from the saved schedule (today ± 7 days).
    @_optimize(none)
    func appointment(id: Int) async throws -> Appointment {
        try await withOfflineCopy {
            try await request(.get, "appointments/\(id)")
        } saved: {
            await offlineCache?.load(ScheduleSnapshot.self, .schedule)?.payload.appointment(id: id)
        }
    }
}
