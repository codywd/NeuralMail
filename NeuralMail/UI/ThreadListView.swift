import SwiftUI

struct ThreadListView: View {
    @ObservedObject var model: InboxViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.mailboxes.isEmpty {
                HStack {
                    Text("Mailbox")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Mailbox", selection: $model.selectedMailboxName) {
                        ForEach(model.mailboxes) { mailbox in
                            Text(mailbox.displayName).tag(Optional(mailbox.name))
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                Divider()
            }

            Group {
                if model.selectedAccount == nil {
                    ContentUnavailableView("No account selected", systemImage: "tray")
                } else if model.isLoading && model.summaries.isEmpty {
                    ProgressView("Loading Inbox…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = model.errorMessage, model.summaries.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView("Unable to load Inbox", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        Button("Retry") {
                            Task { await model.refreshSelected() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $model.selectedUID) {
                        ForEach(model.summaries) { summary in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.subject.isEmpty ? "(No Subject)" : summary.subject)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let preview = summary.preview, !preview.isEmpty {
                                    Text(preview)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 8) {
                                    Text(summary.from.isEmpty ? "Unknown sender" : summary.from)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if let date = summary.date {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tag(summary.uid)
                        }
                    }
                }
            }
        }
        .navigationTitle(model.selectedAccountTitle)
        .onChange(of: model.selectedUID) { _ in
            Task { await model.loadSelectedBody() }
        }
        .onChange(of: model.selectedMailboxName) { newValue in
            Task { await model.selectMailbox(name: newValue) }
        }
    }
}
