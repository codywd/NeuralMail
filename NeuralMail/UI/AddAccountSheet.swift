import SwiftUI

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    @State private var displayName = ""
    @State private var emailAddress = ""
    @State private var username = ""
    @State private var password = ""

    @State private var imapHost = ""
    @State private var imapPort = 993
    @State private var imapSecurity: NMSecurityMode = .tls

    @State private var smtpHost = ""
    @State private var smtpPort = 465
    @State private var smtpSecurity: NMSecurityMode = .tls

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display name", text: $displayName)
                    TextField("Email address", text: $emailAddress)
                    TextField("Username", text: $username)
                    SecureField("Password (stored in Keychain)", text: $password)
                }

                Section("IMAP") {
                    TextField("Host", text: $imapHost)
                    HStack {
                        TextField("Port", value: $imapPort, format: .number)
                            .frame(width: 100)
                        Picker("Security", selection: $imapSecurity) {
                            ForEach(NMSecurityMode.implementedCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }
                    Text("STARTTLS is planned. For now, use TLS (993) or None.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("SMTP") {
                    TextField("Host", text: $smtpHost)
                    HStack {
                        TextField("Port", value: $smtpPort, format: .number)
                            .frame(width: 100)
                        Picker("Security", selection: $smtpSecurity) {
                            ForEach(NMSecurityMode.implementedCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }
                    Text("STARTTLS is planned. For now, use TLS (465) or None.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var canSave: Bool {
        !emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !imapHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !smtpHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        errorMessage = nil

        let account = NMAccount(
            emailAddress: emailAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            imapHost: imapHost.trimmingCharacters(in: .whitespacesAndNewlines),
            imapPort: imapPort,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost.trimmingCharacters(in: .whitespacesAndNewlines),
            smtpPort: smtpPort,
            smtpSecurity: smtpSecurity,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            try KeychainStore.setPassword(password, key: account.passwordKeychainKey)
            appStore.addAccount(account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddAccountSheet()
            .environmentObject(AppStore.preview)
    }
}
