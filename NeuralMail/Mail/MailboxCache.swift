import Foundation

struct MailboxCache: Codable, Hashable, Sendable {
    let accountID: UUID
    let mailbox: String
    var uidValidity: UInt32?
    var uidNext: UInt32?
    var summaries: [MailMessageSummary]
    var lastUpdated: Date
}

struct MailboxCacheKey: Hashable {
    let accountID: UUID
    let mailbox: String
}

@MainActor
protocol MailboxCacheStore: AnyObject {
    func loadMailboxCache(accountID: UUID, mailbox: String) -> MailboxCache?
    func saveMailboxCache(_ cache: MailboxCache)
    func deleteMailboxCache(accountID: UUID, mailbox: String)
}

