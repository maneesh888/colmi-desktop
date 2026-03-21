import Foundation

// MARK: - Background Sync Scheduler
// Handles periodic syncing via:
// 1. Daemon mode (runs continuously in background)
// 2. Launchd integration (macOS native scheduler)

/// Manages background sync scheduling for ColmiSync
struct BackgroundScheduler {
    
    // MARK: - Configuration
    
    /// Default sync interval in minutes
    static let defaultInterval: Int = 60  // 1 hour
    
    /// Config file location
    static let configFile: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colmisync/daemon.json")
    }()
    
    /// Launchd plist location
    static let launchdPlist: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.colmisync.daemon.plist")
    }()
    
    /// Log file location
    static let logFile: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colmisync/daemon.log")
    }()
    
    // MARK: - Daemon Configuration
    
    struct Config: Codable {
        var intervalMinutes: Int = 60
        var historyDays: Int = 7
        var enableMonitoring: Int = 5  // HR monitoring interval on ring
        var minRssi: Int = -80  // Only sync if signal is good
        var quietHoursStart: Int? = nil  // e.g., 23 for 11 PM
        var quietHoursEnd: Int? = nil    // e.g., 7 for 7 AM
        var lastSync: Date? = nil
        var syncCount: Int = 0
        
        static func load() -> Config {
            guard let data = try? Data(contentsOf: configFile),
                  let config = try? JSONDecoder().decode(Config.self, from: data) else {
                return Config()
            }
            return config
        }
        
        func save() {
            try? FileManager.default.createDirectory(
                at: configFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(self) {
                try? data.write(to: configFile)
            }
        }
    }
    
    // MARK: - Daemon Mode
    
    /// Run in daemon mode (continuous background sync)
    @MainActor
    static func runDaemon(intervalMinutes: Int) {
        log("🔄 ColmiSync Daemon starting (interval: \(intervalMinutes) min)")
        
        var config = Config.load()
        config.intervalMinutes = intervalMinutes
        config.save()
        
        // Set up signal handlers for graceful shutdown
        // Note: Can't use closures that capture context for C signal handlers
        signal(SIGTERM, SIG_DFL)  // Use default handler (clean exit)
        signal(SIGINT, SIG_DFL)   // Use default handler (clean exit)
        
        // Initial sync
        performSync(config: config)
        
        // Continuous loop
        while true {
            let nextSync = Date().addingTimeInterval(TimeInterval(config.intervalMinutes * 60))
            log("⏰ Next sync at \(formatTime(nextSync))")
            
            // Sleep until next sync
            Thread.sleep(forTimeInterval: TimeInterval(config.intervalMinutes * 60))
            
            // Reload config in case it changed
            config = Config.load()
            
            // Check quiet hours
            if isQuietHours(config: config) {
                log("🌙 Quiet hours active, skipping sync")
                continue
            }
            
            // Perform sync
            performSync(config: config)
        }
    }
    
    /// Perform a single sync operation
    @MainActor
    private static func performSync(config: Config) {
        log("📡 Starting sync...")
        
        let cli = CLISync()
        cli.scanTimeout = 30
        cli.maxRetries = 2
        cli.historyDays = config.historyDays
        cli.enableMonitoringInterval = config.enableMonitoring
        cli.minRssi = config.minRssi
        cli.run()
        
        // Update config with sync timestamp
        var updatedConfig = Config.load()
        updatedConfig.lastSync = Date()
        updatedConfig.syncCount += 1
        updatedConfig.save()
        
        log("✅ Sync complete (#\(updatedConfig.syncCount))")
    }
    
    /// Check if current time is within quiet hours
    private static func isQuietHours(config: Config) -> Bool {
        guard let start = config.quietHoursStart,
              let end = config.quietHoursEnd else {
            return false
        }
        
        let hour = Calendar.current.component(.hour, from: Date())
        
        if start < end {
            // Simple case: e.g., 23-07 spans midnight
            return hour >= start || hour < end
        } else {
            // Spans midnight: e.g., 23-07
            return hour >= start || hour < end
        }
    }
    
    // MARK: - Launchd Integration
    
    /// Install launchd agent for automatic startup
    static func installLaunchd(intervalMinutes: Int, historyDays: Int) {
        let execPath = ProcessInfo.processInfo.arguments[0]
        
        // Create plist content
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.colmisync.daemon</string>
            
            <key>ProgramArguments</key>
            <array>
                <string>\(execPath)</string>
                <string>--cli</string>
                <string>--history</string>
                <string>\(historyDays)</string>
                <string>--enable-monitoring</string>
                <string>5</string>
            </array>
            
            <key>StartInterval</key>
            <integer>\(intervalMinutes * 60)</integer>
            
            <key>RunAtLoad</key>
            <true/>
            
            <key>StandardOutPath</key>
            <string>\(logFile.path)</string>
            
            <key>StandardErrorPath</key>
            <string>\(logFile.path)</string>
            
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/usr/local/bin:/usr/bin:/bin</string>
            </dict>
        </dict>
        </plist>
        """
        
        do {
            // Create LaunchAgents directory if needed
            try FileManager.default.createDirectory(
                at: launchdPlist.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Write plist
            try plist.write(to: launchdPlist, atomically: true, encoding: .utf8)
            
            // Load the agent
            let result = shell("launchctl load \(launchdPlist.path)")
            if result.contains("error") || result.contains("Error") {
                print("⚠️ Warning: \(result)")
            }
            
            print("✅ Launchd agent installed!")
            print("   Sync interval: every \(intervalMinutes) minutes")
            print("   History days: \(historyDays)")
            print("   Log file: \(logFile.path)")
            print("")
            print("📋 Commands:")
            print("   Check status: launchctl list | grep colmisync")
            print("   View logs: tail -f \(logFile.path)")
            print("   Uninstall: ColmiSync --uninstall-daemon")
            
            // Save config
            var config = Config()
            config.intervalMinutes = intervalMinutes
            config.historyDays = historyDays
            config.save()
            
        } catch {
            print("❌ Failed to install launchd agent: \(error)")
        }
    }
    
    /// Uninstall launchd agent
    static func uninstallLaunchd() {
        // Unload the agent first
        _ = shell("launchctl unload \(launchdPlist.path) 2>/dev/null")
        
        // Remove plist file
        do {
            if FileManager.default.fileExists(atPath: launchdPlist.path) {
                try FileManager.default.removeItem(at: launchdPlist)
                print("✅ Launchd agent uninstalled")
            } else {
                print("ℹ️ Launchd agent was not installed")
            }
        } catch {
            print("❌ Failed to remove plist: \(error)")
        }
    }
    
    /// Check daemon status
    static func status() {
        print("📊 ColmiSync Daemon Status")
        print("=" .padding(toLength: 40, withPad: "=", startingAt: 0))
        
        // Check launchd
        let launchdStatus = shell("launchctl list 2>/dev/null | grep colmisync")
        if !launchdStatus.isEmpty {
            print("🟢 Launchd agent: RUNNING")
            print("   \(launchdStatus.trimmingCharacters(in: .whitespacesAndNewlines))")
        } else if FileManager.default.fileExists(atPath: launchdPlist.path) {
            print("🟡 Launchd agent: INSTALLED but not running")
            print("   Try: launchctl load \(launchdPlist.path)")
        } else {
            print("⚪ Launchd agent: NOT INSTALLED")
        }
        
        // Load config
        let config = Config.load()
        print("")
        print("⚙️ Configuration:")
        print("   Interval: \(config.intervalMinutes) minutes")
        print("   History days: \(config.historyDays)")
        print("   Min RSSI: \(config.minRssi)")
        if let start = config.quietHoursStart, let end = config.quietHoursEnd {
            print("   Quiet hours: \(start):00 - \(end):00")
        }
        
        print("")
        print("📈 Statistics:")
        print("   Total syncs: \(config.syncCount)")
        if let lastSync = config.lastSync {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: lastSync, relativeTo: Date())
            print("   Last sync: \(relative)")
        } else {
            print("   Last sync: never")
        }
        
        // Check log file
        if FileManager.default.fileExists(atPath: logFile.path) {
            print("")
            print("📜 Recent log:")
            let recentLog = shell("tail -5 \(logFile.path)")
            for line in recentLog.split(separator: "\n").prefix(5) {
                print("   \(line)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line)
        fflush(stdout)
        
        // Also write to log file
        let dir = logFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? (line + "\n").write(to: logFile, atomically: false, encoding: .utf8)
        }
    }
    
    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private static func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/sh"
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
