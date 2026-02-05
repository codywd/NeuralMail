import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Accounts") {
                Text("Account setup currently supports Generic IMAP/SMTP.")
            }

            Section("AI") {
                Text("AI profiles will be wired in after mail sync is stable.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 360)
        .navigationTitle("Settings")
        .padding()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
