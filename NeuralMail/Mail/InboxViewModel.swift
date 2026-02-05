import Foundation
import Combine
import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var selectedAccount: NMAccount?
    @Published var summaries: [MailMessageSummary] = []
    @Published var selectedUID: UInt32?
    @Published var selectedBody: String?

    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var isLoadingBody = false
    @Published var bodyErrorMessage: String?

    private let service = IMAPInboxService()

    var selectedAccountTitle: String {
        guard let selectedAccount else { return "Inbox" }
        return selectedAccount.displayName.isEmpty ? selectedAccount.emailAddress : selectedAccount.displayName
    }

    func selectAccount(_ account: NMAccount?) {
        selectedAccount = account
        summaries = []
        selectedUID = nil
        selectedBody = nil
        errorMessage = nil
        bodyErrorMessage = nil

        guard account != nil else { return }
        Task { await refreshSelected() }
    }

    func refreshSelected() async {
        guard let account = selectedAccount else { return }

        isLoading = true
        errorMessage = nil

        do {
            guard let password = try KeychainStore.getPassword(key: account.passwordKeychainKey) else {
                throw NSError(domain: "NeuralMail", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing password in Keychain for this account."])
            }

            let config = IMAPConfiguration(
                host: account.imapHost,
                port: account.imapPort,
                security: account.imapSecurity,
                username: account.username,
                password: password
            )

            let loaded = try await service.fetchInboxSummaries(config: config, limit: 50)
            summaries = loaded.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
            if selectedUID == nil {
                selectedUID = summaries.first?.uid
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadSelectedBody() async {
        guard let account = selectedAccount, let uid = selectedUID else { return }

        isLoadingBody = true
        bodyErrorMessage = nil
        selectedBody = nil

        do {
            guard let password = try KeychainStore.getPassword(key: account.passwordKeychainKey) else {
                throw NSError(domain: "NeuralMail", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing password in Keychain for this account."])
            }

            let config = IMAPConfiguration(
                host: account.imapHost,
                port: account.imapPort,
                security: account.imapSecurity,
                username: account.username,
                password: password
            )

            selectedBody = try await service.fetchMessageBody(config: config, uid: uid)
        } catch {
            bodyErrorMessage = error.localizedDescription
        }

        isLoadingBody = false
    }
}
