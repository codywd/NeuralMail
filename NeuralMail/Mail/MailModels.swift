import Foundation

struct MailMessageSummary: Identifiable, Hashable, Sendable, Codable {
    var id: UInt32 { uid }
    let uid: UInt32
    let subject: String
    let from: String
    let date: Date?
    let preview: String?
}

struct IMAPMailbox: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String

    var displayName: String {
        name
    }
}
