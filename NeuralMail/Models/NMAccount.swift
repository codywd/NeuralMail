import Foundation

struct NMAccount: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var emailAddress: String
    var displayName: String

    var imapHost: String
    var imapPort: Int
    var imapSecurity: NMSecurityMode

    var smtpHost: String
    var smtpPort: Int
    var smtpSecurity: NMSecurityMode

    var username: String

    init(
        id: UUID = UUID(),
        emailAddress: String,
        displayName: String,
        imapHost: String,
        imapPort: Int,
        imapSecurity: NMSecurityMode,
        smtpHost: String,
        smtpPort: Int,
        smtpSecurity: NMSecurityMode,
        username: String
    ) {
        self.id = id
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.imapSecurity = imapSecurity
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.smtpSecurity = smtpSecurity
        self.username = username
    }
}

enum NMSecurityMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case tls = "TLS"
    case starttls = "STARTTLS"
    case none = "None"

    var id: String { rawValue }

    static var implementedCases: [NMSecurityMode] {
        [.tls, .none]
    }
}

extension NMAccount {
    var passwordKeychainKey: String {
        "account.\(id.uuidString).password"
    }
}
