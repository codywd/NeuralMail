//
//  ContentView.swift
//  NeuralMail
//
//  Created by Cody Dostal on 2/4/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var selectedAccountID: UUID?
    @StateObject private var inboxModel = InboxViewModel()
    @State private var showingAddAccount = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedAccountID) {
                Section("Accounts") {
                    ForEach(appStore.accounts) { account in
                        Text(account.displayName.isEmpty ? account.emailAddress : account.displayName)
                            .tag(account.id)
                    }
                    .onDelete(perform: deleteAccounts)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }

                    Button {
                        Task { await inboxModel.refreshSelected() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(inboxModel.selectedAccount == nil)
                }
            }
        } content: {
            ThreadListView(model: inboxModel)
        } detail: {
            MessageDetailView(model: inboxModel)
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountSheet()
                .environmentObject(appStore)
        }
        .onAppear {
            inboxModel.attachCacheStore(appStore)
            if selectedAccountID == nil {
                selectedAccountID = appStore.accounts.first?.id
            }
        }
        .onChange(of: selectedAccountID) { newValue in
            let selected = appStore.accounts.first(where: { $0.id == newValue })
            inboxModel.selectAccount(selected)
        }
    }

    private func deleteAccounts(offsets: IndexSet) {
        appStore.deleteAccounts(offsets: offsets)
        if let selectedAccountID, !appStore.accounts.contains(where: { $0.id == selectedAccountID }) {
            self.selectedAccountID = appStore.accounts.first?.id
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore.preview)
    }
}
