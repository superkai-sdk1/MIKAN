import Foundation

/// Server address persisted in UserDefaults (editable on the login screen).
nonisolated enum ServerConfig {
    static let defaultAddress = "https://95-170-124-192.sslip.io"
    private static let addressKey = "serverAddress"

    static var savedAddress: String {
        UserDefaults.standard.string(forKey: addressKey) ?? defaultAddress
    }

    static var url: URL {
        normalize(savedAddress) ?? normalize(defaultAddress) ?? URL(filePath: "/")
    }

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: addressKey)
    }

    /// Accepts "host", "https://host/", "http://localhost:3000/api" and returns the origin URL.
    static func normalize(_ raw: String) -> URL? {
        var address = raw.trimmed
        guard !address.isEmpty else { return nil }
        if !address.contains("://") {
            let isLocal = address.hasPrefix("localhost") || address.hasPrefix("127.") || address.hasPrefix("192.168.")
            address = (isLocal ? "http://" : "https://") + address
        }
        while address.hasSuffix("/") { address.removeLast() }
        if address.lowercased().hasSuffix("/api") { address.removeLast(4) }
        while address.hasSuffix("/") { address.removeLast() }
        guard
            let url = URL(string: address),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
}

/// Last signed-in employee, so the app can start offline before `/auth/me` answers. Not sensitive.
nonisolated enum SessionCache {
    private static let employeeKey = "cachedEmployee"

    static var employee: Employee? {
        get {
            guard let data = UserDefaults.standard.data(forKey: employeeKey) else { return nil }
            return try? JSONCoding.makeDecoder().decode(Employee.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONCoding.makeEncoder().encode(newValue) else {
                UserDefaults.standard.removeObject(forKey: employeeKey)
                return
            }
            UserDefaults.standard.set(data, forKey: employeeKey)
        }
    }
}
