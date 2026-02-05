import SwiftUI

struct MessageDetailView: View {
    @ObservedObject var model: InboxViewModel

    var body: some View {
        Group {
            if model.selectedUID == nil {
                ContentUnavailableView("Select a message", systemImage: "envelope.open")
            } else if model.isLoadingBody {
                ProgressView("Loading message…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.bodyErrorMessage {
                ContentUnavailableView("Unable to load message", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ScrollView {
                    Text(model.selectedBody ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
    }
}
