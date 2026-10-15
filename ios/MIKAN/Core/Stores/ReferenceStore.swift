import Foundation
import Observation

/// Cached reference data used by pickers: employees (masters), services, aftercare templates.
@Observable
final class ReferenceStore {
    private let api: APIClient
    private(set) var employees: [Employee] = []
    private(set) var services: [Service] = []
    private(set) var templates: [AftercareTemplate] = []
    private var loadedEmployees = false
    private var loadedServices = false
    private var loadedTemplates = false

    init(api: APIClient) {
        self.api = api
    }

    /// Active employees who perform procedures.
    var masters: [Employee] { employees.filter { $0.isMaster && $0.active } }
    var activeServices: [Service] { services.filter(\.active) }

    func service(id: Int?) -> Service? {
        guard let id else { return nil }
        return services.first { $0.id == id }
    }

    func template(id: Int?) -> AftercareTemplate? {
        guard let id else { return nil }
        return templates.first { $0.id == id }
    }

    func ensureEmployees(force: Bool = false) async throws {
        guard force || !loadedEmployees else { return }
        employees = try await api.employees(includeInactive: true)
        loadedEmployees = true
    }

    func ensureServices(force: Bool = false) async throws {
        guard force || !loadedServices else { return }
        services = try await api.services(includeInactive: true)
        loadedServices = true
    }

    func ensureTemplates(force: Bool = false) async throws {
        guard force || !loadedTemplates else { return }
        templates = try await api.aftercareTemplates()
        loadedTemplates = true
    }

    func replaceEmployees(_ items: [Employee]) {
        employees = items
        loadedEmployees = true
    }

    func replaceServices(_ items: [Service]) {
        services = items
        loadedServices = true
    }

    func replaceTemplates(_ items: [AftercareTemplate]) {
        templates = items
        loadedTemplates = true
    }

    func reset() {
        employees = []
        services = []
        templates = []
        loadedEmployees = false
        loadedServices = false
        loadedTemplates = false
    }
}
