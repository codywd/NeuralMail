//
//  NeuralMailApp.swift
//  NeuralMail
//
//  Created by Cody Dostal on 2/4/26.
//

import SwiftUI

@main
struct NeuralMailApp: App {
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStore)
        }
        
        Settings {
            SettingsView()
                .environmentObject(appStore)
        }
    }
}
