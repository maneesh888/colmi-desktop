import SwiftUI

@main
struct ColmiSyncApp: App {
    @StateObject private var bleManager = BLEManager()
    
    init() {
        // Check for CLI mode
        if CommandLine.arguments.contains("--cli") || CommandLine.arguments.contains("--sync") {
            let args = CLISync.parseArgs(CommandLine.arguments)
            let cli = CLISync()
            cli.scanTimeout = TimeInterval(args.scanTime)
            cli.maxRetries = args.retries
            cli.historyDays = args.historyDays
            cli.enableMonitoringInterval = args.enableMonitoring
            cli.run()
            exit(0)
        }
    }
    
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
