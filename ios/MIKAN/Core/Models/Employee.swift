import Foundation

/// Staff member. All employees have identical permissions; `isMaster` marks people who perform procedures.
nonisolated struct Employee: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    var name: String
    var login: String
    var phone: String?
    var color: String?
    var isMaster: Bool
    var active: Bool
    let createdAt: Date

    var ref: EmployeeRef { EmployeeRef(id: id, name: name, color: color) }
}

/// Embedded employee summary used inside other entities.
nonisolated struct EmployeeRef: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let color: String?
}
