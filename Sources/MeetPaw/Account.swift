import Foundation

/// A signed-in account (one provider + one identity). Token lives in Keychain
/// under `id`; the registry (list of accounts, emails only) lives in UserDefaults.
struct Account: Codable, Identifiable, Hashable {
    let provider: Provider
    let email: String
    var id: String { "\(provider.rawValue):\(email.lowercased())" }

    var shortEmail: String {
        email.count > 28 ? String(email.prefix(26)) + "…" : email
    }
}

/// A calendar event tagged with the account it came from (ids collide across
/// accounts, so the composite id keeps them distinct).
struct AccountEvent: Identifiable, Equatable, Hashable {
    let account: Account
    let event: CalendarEvent
    var id: String { account.id + "|" + event.id }
    static func == (a: AccountEvent, b: AccountEvent) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum AccountStore {
    private static let key = "accounts.v1"

    static func load() -> [Account] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Account].self, from: data) else { return [] }
        return list
    }

    static func save(_ accounts: [Account]) {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(_ account: Account) {
        var list = load().filter { $0.id != account.id }   // dedupe by id
        list.append(account)
        save(list)
    }

    static func remove(_ account: Account) {
        save(load().filter { $0.id != account.id })
    }
}
