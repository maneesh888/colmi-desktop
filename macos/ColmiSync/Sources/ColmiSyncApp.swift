import SwiftUI

@main
struct ColmiSyncApp: App {
    @StateObject private var bleManager = BLEManager()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(bleManager)
        } label: {
            Image(systemName: bleManager.isConnected ? "heart.fill" : "heart")
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environmentObject(bleManager)
        }
    }
}
