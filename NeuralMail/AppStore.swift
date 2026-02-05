import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var accounts: [NMAccount] = []
    @Published private(set) var aiProfiles: [NMAIProfile] = []

    private let accountsKey = "NeuralMail.accounts.v1"
    private let aiProfilesKey = "NeuralMail.aiProfiles.v1"
    private let mailboxCachesKey = "NeuralMail.mailboxCaches.v1"

    private var mailboxCaches: [MailboxCacheKey: MailboxCache] = [:]

    init(loadFromDefaults: Bool = true) {
        guard loadFromDefaults else { return }
        accounts = Self.load([NMAccount].self, key: accountsKey) ?? []
        aiProfiles = Self.load([NMAIProfile].self, key: aiProfilesKey) ?? []
        accounts.sort(by: Self.accountSort)
        if let caches = Self.load([MailboxCache].self, key: mailboxCachesKey) {
            mailboxCaches = Dictionary(uniqueKeysWithValues: caches.map { cache in
                (MailboxCacheKey(accountID: cache.accountID, mailbox: cache.mailbox), cache)
            })
        }
    }

    func addAccount(_ account: NMAccount) {
        accounts.append(account)
        accounts.sort(by: Self.accountSort)
        persistAccounts()
    }

    func deleteAccounts(offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            try? KeychainStore.delete(key: account.passwordKeychainKey)
            deleteAllMailboxCaches(accountID: account.id)
        }
        for index in offsets.sorted(by: >) {
            accounts.remove(at: index)
        }
        persistAccounts()
    }

    func upsertAIProfile(_ profile: NMAIProfile) {
        if let idx = aiProfiles.firstIndex(where: { $0.id == profile.id }) {
            aiProfiles[idx] = profile
        } else {
            aiProfiles.append(profile)
        }
        persistAIProfiles()
    }

    private func persistAccounts() {
        Self.save(accounts, key: accountsKey)
    }

    private func persistAIProfiles() {
        Self.save(aiProfiles, key: aiProfilesKey)
    }

    private func persistMailboxCaches() {
        Self.save(Array(mailboxCaches.values), key: mailboxCachesKey)
    }

    private func deleteAllMailboxCaches(accountID: UUID) {
        mailboxCaches = mailboxCaches.filter { $0.key.accountID != accountID }
        persistMailboxCaches()
    }

    private static func accountSort(_ a: NMAccount, _ b: NMAccount) -> Bool {
        a.emailAddress.localizedCaseInsensitiveCompare(b.emailAddress) == .orderedAscending
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension AppStore {
    static var preview: AppStore {
        let store = AppStore(loadFromDefaults: false)
        store.accounts = [
            NMAccount(
                emailAddress: "jane@example.com",
                displayName: "Jane Example",
                imapHost: "imap.example.com",
                imapPort: 993,
                imapSecurity: .tls,
                smtpHost: "smtp.example.com",
                smtpPort: 465,
                smtpSecurity: .tls,
                username: "jane@example.com"
            ),
        ]
        return store
    }
}

extension AppStore: MailboxCacheStore {
    func loadMailboxCache(accountID: UUID, mailbox: String) -> MailboxCache? {
        mailboxCaches[MailboxCacheKey(accountID: accountID, mailbox: mailbox)]
    }

    func saveMailboxCache(_ cache: MailboxCache) {
        mailboxCaches[MailboxCacheKey(accountID: cache.accountID, mailbox: cache.mailbox)] = cache
        persistMailboxCaches()
    }

    func deleteMailboxCache(accountID: UUID, mailbox: String) {
        mailboxCaches.removeValue(forKey: MailboxCacheKey(accountID: accountID, mailbox: mailbox))
        persistMailboxCaches()
    }
}
