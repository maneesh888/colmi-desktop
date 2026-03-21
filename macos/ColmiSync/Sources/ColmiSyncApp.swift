import SwiftUI

@main
struct ColmiSyncApp: App {
    @StateObject private var bleManager = BLEManager()
    
    init() {
        let args = CommandLine.arguments
        
        // Help
        if args.contains("--help") || args.contains("-h") {
            printHelp()
            exit(0)
        }
        
        // Check for summary mode (no Bluetooth needed)
        if args.contains("--summary") {
            HealthSummary.printSummary(days: 7)
            exit(0)
        }
        
        // Daemon commands (background sync scheduler)
        if args.contains("--daemon") {
            let interval = parseDaemonInterval(args)
            BackgroundScheduler.runDaemon(intervalMinutes: interval)
            exit(0)  // Never reached, daemon loops forever
        }
        
        if args.contains("--install-daemon") {
            let interval = parseDaemonInterval(args)
            let history = parseDaemonHistory(args)
            BackgroundScheduler.installLaunchd(intervalMinutes: interval, historyDays: history)
            exit(0)
        }
        
        if args.contains("--uninstall-daemon") {
            BackgroundScheduler.uninstallLaunchd()
            exit(0)
        }
        
        if args.contains("--daemon-status") {
            BackgroundScheduler.status()
            exit(0)
        }
        
        // Check for CLI mode
        if args.contains("--cli") || args.contains("--sync") || args.contains("--scan-only") || args.contains("--history") {
            let parsed = CLISync.parseArgs(args)
            let cli = CLISync()
            cli.scanTimeout = TimeInterval(parsed.scanTime)
            cli.maxRetries = parsed.retries
            cli.historyDays = parsed.historyDays
            cli.enableMonitoringInterval = parsed.enableMonitoring
            cli.minRssi = parsed.minRssi
            cli.scanOnly = parsed.scanOnly
            cli.run()
            exit(0)
        }
    }
    
    /// Parse --daemon or --install-daemon interval (default 60 min)
    private func parseDaemonInterval(_ args: [String]) -> Int {
        guard let idx = args.firstIndex(of: "--interval"),
              idx + 1 < args.count,
              let val = Int(args[idx + 1]), val > 0 else {
            return 60  // Default 1 hour
        }
        return val
    }
    
    /// Parse --install-daemon history days (default 7)
    private func parseDaemonHistory(_ args: [String]) -> Int {
        guard let idx = args.firstIndex(of: "--history"),
              idx + 1 < args.count,
              let val = Int(args[idx + 1]), val > 0 else {
            return 7  // Default 7 days
        }
        return val
    }
    
    /// Print help text
    private func printHelp() {
        print("""
        ColmiSync - Privacy-first Colmi smart ring sync tool
        
        USAGE:
            ColmiSync [OPTIONS]
        
        SYNC OPTIONS:
            --cli, --sync          Run single sync (battery, HR, SpO2)
            --history [DAYS]       Sync history data (default: 7 days)
            --enable-monitoring N  Enable continuous HR monitoring (N minutes)
            --scan-time N          BLE scan timeout in seconds (default: 30)
            --retries N            Max connection retries (default: 3)
            --min-rssi N           Min signal strength to sync (default: -100)
            --scan-only            Just scan for ring, don't sync
        
        DAEMON OPTIONS:
            --install-daemon       Install background sync via launchd
            --uninstall-daemon     Remove background sync from launchd
            --daemon-status        Show daemon status and sync stats
            --daemon               Run daemon inline (for testing)
            --interval N           Daemon sync interval in minutes (default: 60)
        
        OTHER:
            --summary              Print health summary (last 7 days)
            --help, -h             Show this help
        
        EXAMPLES:
            # Single sync with 3 days history
            ColmiSync --cli --history 3
            
            # Install daemon, sync every 30 min, keep 7 days history
            ColmiSync --install-daemon --interval 30 --history 7
            
            # Check daemon status
            ColmiSync --daemon-status
        
        DATA LOCATION:
            ~/clawd/health/       Health data (JSON files)
            ~/.colmisync/         Config and logs
        """)
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
