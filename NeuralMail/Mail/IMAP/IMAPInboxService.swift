import Foundation

struct IMAPConfiguration: Sendable {
    let host: String
    let port: Int
    let security: NMSecurityMode
    let username: String
    let password: String
}

struct IMAPInboxService {
    func fetchInboxSummaries(config: IMAPConfiguration, limit: Int) async throws -> [MailMessageSummary] {
        let client = IMAPClient(config: config)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        try await client.login()
        try await client.selectMailbox("INBOX")

        let uids = try await client.uidSearchAll()
        let recent = Array(uids.suffix(max(0, limit)))
        guard !recent.isEmpty else { return [] }

        let headersByUID = try await client.fetchHeaders(uids: recent)
        return recent.compactMap { uid in
            guard let headers = headersByUID[uid] else { return nil }
            return MailMessageSummary(
                uid: uid,
                subject: headers.subject,
                from: headers.from,
                date: headers.date
            )
        }
    }

    func fetchMessageBody(config: IMAPConfiguration, uid: UInt32) async throws -> String {
        let client = IMAPClient(config: config)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        try await client.login()
        try await client.selectMailbox("INBOX")

        let data = try await client.fetchBodyText(uid: uid)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

