import Foundation
import Combine
import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var selectedAccount: NMAccount?
    @Published var summaries: [MailMessageSummary] = []
    @Published var selectedUID: UInt32?
    @Published var selectedBody: String?
    @Published var mailboxes: [IMAPMailbox] = []
    @Published var selectedMailboxName: String?

    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var isLoadingBody = false
    @Published var bodyErrorMessage: String?

    private var service: IMAPInboxService?
    private var serviceAccountID: UUID?
    private var cacheStore: MailboxCacheStore?

    var selectedAccountTitle: String {
        guard let selectedAccount else { return "Inbox" }
        return selectedAccount.displayName.isEmpty ? selectedAccount.emailAddress : selectedAccount.displayName
    }

    func selectAccount(_ account: NMAccount?) {
        if service != nil, serviceAccountID != account?.id {
            Task { await service?.disconnect() }
            service = nil
            serviceAccountID = nil
        }

        selectedAccount = account
        summaries = []
        selectedUID = nil
        selectedBody = nil
        mailboxes = []
        selectedMailboxName = nil
        errorMessage = nil
        bodyErrorMessage = nil

        guard account != nil else { return }
        Task { await loadMailboxesAndRefresh() }
    }

    func attachCacheStore(_ store: MailboxCacheStore) {
        cacheStore = store
    }

    func refreshSelected() async {
        guard let account = selectedAccount else { return }

        isLoading = true
        errorMessage = nil

        do {
            let mailbox = selectedMailboxName ?? "INBOX"
            let service = try await getOrCreateService(for: account)

            var cache = cacheStore?.loadMailboxCache(accountID: account.id, mailbox: mailbox)
            if let cache, summaries.isEmpty {
                summaries = sortSummaries(cache.summaries)
                selectedUID = selectedUID ?? summaries.first?.uid
            }

            let status = try await service.mailboxStatus(mailbox)
            if let cachedValidity = cache?.uidValidity, let serverValidity = status.uidValidity, cachedValidity != serverValidity {
                cache = nil
                summaries = []
                selectedUID = nil
            }

            var updatedSummaries: [MailMessageSummary]

            if cache == nil {
                let initial = try await service.fetchMessageSummaries(mailbox: mailbox, limit: 50)
                updatedSummaries = initial
            } else if let cachedNext = cache?.uidNext, let serverNext = status.uidNext, serverNext > cachedNext {
                let end = serverNext > 0 ? serverNext - 1 : serverNext
                let newUIDs = try await service.searchUIDs(mailbox: mailbox, start: cachedNext, end: end)
                let newSummaries = try await service.fetchMessageSummaries(mailbox: mailbox, uids: newUIDs)
                updatedSummaries = mergeSummaries(existing: cache?.summaries ?? [], new: newSummaries)
            } else {
                updatedSummaries = cache?.summaries ?? []
            }

            summaries = sortSummaries(updatedSummaries)
            if selectedUID == nil {
                selectedUID = summaries.first?.uid
            }

            let newCache = MailboxCache(
                accountID: account.id,
                mailbox: mailbox,
                uidValidity: status.uidValidity ?? cache?.uidValidity,
                uidNext: status.uidNext ?? cache?.uidNext,
                summaries: updatedSummaries,
                lastUpdated: Date()
            )
            cacheStore?.saveMailboxCache(newCache)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMailboxesAndRefresh() async {
        guard let account = selectedAccount else { return }
        isLoading = true
        errorMessage = nil

        do {
            let service = try await getOrCreateService(for: account)
            let listed = try await service.listMailboxes()
            mailboxes = listed
            if selectedMailboxName == nil {
                if mailboxes.contains(where: { $0.name.uppercased() == "INBOX" }) {
                    selectedMailboxName = "INBOX"
                } else {
                    selectedMailboxName = mailboxes.first?.name
                }
            }
            await refreshSelected()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func selectMailbox(name: String?) async {
        selectedMailboxName = name
        selectedUID = nil
        selectedBody = nil
        await refreshSelected()
    }

    private func getOrCreateService(for account: NMAccount) async throws -> IMAPInboxService {
        if let service, serviceAccountID == account.id {
            return service
        }

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

        let newService = IMAPInboxService(config: config)
        service = newService
        serviceAccountID = account.id
        return newService
    }

    func loadSelectedBody() async {
        guard let account = selectedAccount, let uid = selectedUID else { return }

        isLoadingBody = true
        bodyErrorMessage = nil
        selectedBody = nil

        do {
            let mailbox = selectedMailboxName ?? "INBOX"
            let service = try await getOrCreateService(for: account)
            selectedBody = try await service.fetchMessageBody(mailbox: mailbox, uid: uid)
        } catch {
            bodyErrorMessage = error.localizedDescription
        }

        isLoadingBody = false
    }

    private func mergeSummaries(existing: [MailMessageSummary], new: [MailMessageSummary]) -> [MailMessageSummary] {
        var map: [UInt32: MailMessageSummary] = [:]
        for summary in existing {
            map[summary.uid] = summary
        }
        for summary in new {
            map[summary.uid] = summary
        }
        return Array(map.values)
    }

    private func sortSummaries(_ summaries: [MailMessageSummary]) -> [MailMessageSummary] {
        summaries.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
    }
}
