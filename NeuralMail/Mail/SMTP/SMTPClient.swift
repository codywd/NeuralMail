import Foundation

/// Phase 1 stub: compose/sending will be implemented after IMAP sync is stable.
struct SMTPClient {
    struct Configuration: Sendable {
        let host: String
        let port: Int
        let security: NMSecurityMode
        let username: String
        let password: String
    }

    let config: Configuration

    func sendMail(from: String, to: [String], rawRFC822: Data) async throws {
        throw NSError(
            domain: "NeuralMail",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: "SMTP send is not implemented yet."]
        )
    }
}

