import Foundation

struct IMAPConfiguration: Sendable {
    let host: String
    let port: Int
    let security: NMSecurityMode
    let username: String
    let password: String
}

actor IMAPInboxService {
    private let config: IMAPConfiguration
    private let client: IMAPClient
    private var isConnected = false
    private var isLoggedIn = false
    private var selectedMailbox: String?

    init(config: IMAPConfiguration) {
        self.config = config
        self.client = IMAPClient(config: config)
    }

    func connectAndLoginIfNeeded() async throws {
        if !isConnected {
            try await client.connect()
            isConnected = true
        }
        if !isLoggedIn {
            try await client.login()
            isLoggedIn = true
        }
    }

    func disconnect() async {
        await client.disconnect()
        isConnected = false
        isLoggedIn = false
        selectedMailbox = nil
    }

    func listMailboxes() async throws -> [IMAPMailbox] {
        try await connectAndLoginIfNeeded()
        let names = try await client.listMailboxes()
        return names.map { IMAPMailbox(name: $0) }
    }

    func mailboxStatus(_ name: String) async throws -> IMAPMailboxStatus {
        try await connectAndLoginIfNeeded()
        return try await client.mailboxStatus(name)
    }

    func searchUIDs(mailbox: String, start: UInt32, end: UInt32?) async throws -> [UInt32] {
        try await selectMailbox(mailbox)
        return try await client.uidSearchRange(start: start, end: end)
    }

    func selectMailbox(_ name: String) async throws {
        try await connectAndLoginIfNeeded()
        if selectedMailbox != name {
            try await client.selectMailbox(name)
            selectedMailbox = name
        }
    }

    func fetchMessageSummaries(mailbox: String, limit: Int) async throws -> [MailMessageSummary] {
        try await selectMailbox(mailbox)

        let uids = try await client.uidSearchAll()
        let recent = Array(uids.suffix(max(0, limit)))
        guard !recent.isEmpty else { return [] }

        let fetched = try await client.fetchHeadersAndPreview(uids: recent)
        return recent.compactMap { uid in
            guard let entry = fetched[uid] else { return nil }
            let preview = IMAPBodyPreviewParser.previewText(from: entry.previewData)
            return MailMessageSummary(
                uid: uid,
                subject: entry.headers.subject,
                from: entry.headers.from,
                date: entry.headers.date,
                preview: preview
            )
        }
    }

    func fetchMessageSummaries(mailbox: String, uids: [UInt32]) async throws -> [MailMessageSummary] {
        guard !uids.isEmpty else { return [] }
        try await selectMailbox(mailbox)
        let fetched = try await client.fetchHeadersAndPreview(uids: uids)
        return uids.compactMap { uid in
            guard let entry = fetched[uid] else { return nil }
            let preview = IMAPBodyPreviewParser.previewText(from: entry.previewData)
            return MailMessageSummary(
                uid: uid,
                subject: entry.headers.subject,
                from: entry.headers.from,
                date: entry.headers.date,
                preview: preview
            )
        }
    }

    func fetchMessageBody(mailbox: String, uid: UInt32) async throws -> String {
        try await selectMailbox(mailbox)
        let data = try await client.fetchBodyText(uid: uid)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}
