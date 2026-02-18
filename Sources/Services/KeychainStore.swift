import Foundation

final class LocalStore {
    private let defaults: UserDefaults
    private let service: String

    init(service: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.service = service
    }

    func saveString(_ value: String, account: String) throws {
        defaults.set(value, forKey: namespacedKey(account: account))
    }

    func readString(account: String) throws -> String? {
        defaults.string(forKey: namespacedKey(account: account))
    }

    func deleteString(account: String) throws {
        defaults.removeObject(forKey: namespacedKey(account: account))
    }

    private func namespacedKey(account: String) -> String {
        "\(service).\(account)"
    }
}
