import Foundation

struct MailMessageSummary: Identifiable, Hashable, Sendable {
    var id: UInt32 { uid }
    let uid: UInt32
    let subject: String
    let from: String
    let date: Date?
}

struct IMAPMailbox: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String

    var displayName: String {
        name
    }
}
