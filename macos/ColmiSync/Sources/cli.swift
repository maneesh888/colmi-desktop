import Foundation
import CoreBluetooth

// Simple CLI sync tool - runs once, syncs, exits
// Usage: swift run ColmiSync --cli [--scan-time 30]

// Force unbuffered stdout
private func log(_ message: String) {
    print(message)
    fflush(stdout)
}

@MainActor
class CLISync: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var savedRingId: UUID?
    private var savedRingName: String?
    
    private var pendingResponse: ((Data?) -> Void)?
    private let semaphore = DispatchSemaphore(value: 0)
    
    // Configurable settings
    var scanTimeout: TimeInterval = 30  // Default 30 seconds
    var maxRetries: Int = 3
    var historyDays: Int = 0  // 0 = no history sync
    var enableMonitoringInterval: Int = 0  // 0 = don't change, >0 = enable with interval in minutes
    var minRssi: Int = -100  // Minimum RSSI to attempt connection (-100 = any)
    var scanOnly: Bool = false  // Just scan for ring, don't sync
    
    private var lastSeenRssi: Int = -100
    
    override init() {
        super.init()
        loadSavedRing()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        log("🔄 ColmiSync CLI - Starting...")
        
        // Wait for Bluetooth to be ready (up to 10 seconds for daemon mode)
        var btWaitTime = 0
        while centralManager.state != .poweredOn && btWaitTime < 10 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
            btWaitTime += 1
        }
        
        log("🔵 Bluetooth state: \(centralManager.state.rawValue) (waited \(btWaitTime)s)")
        
        guard centralManager.state == .poweredOn else {
            log("❌ Bluetooth not available (state=\(centralManager.state.rawValue))")
            return
        }
        
        // Scan-only mode: just check if ring is nearby with good signal
        if scanOnly {
            log("📡 Scan-only mode - checking for ring...")
            
            // First try to retrieve already-paired peripheral
            if let ringId = savedRingId {
                let peripherals = centralManager.retrievePeripherals(withIdentifiers: [ringId])
                if let p = peripherals.first {
                    log("📱 Found paired ring via system cache!")
                    log("✅ Ring is available for connection")
                    return
                }
                log("🔍 Ring not in system cache, scanning...")
            }
            
            let rssi = scanForRing()
            if rssi > -100 {
                log("📱 Ring found! RSSI: \(rssi)")
                if rssi >= minRssi {
                    log("✅ Signal good enough for sync (>= \(minRssi))")
                } else {
                    log("⚠️ Signal too weak for sync (need >= \(minRssi))")
                }
            } else {
                log("❌ Ring not found via scan")
            }
            return
        }
        
        // Check signal strength first if min-rssi is set
        if minRssi > -100 {
            log("📡 Checking signal strength (need >= \(minRssi))...")
            let rssi = scanForRing()
            if rssi < minRssi {
                log("⚠️ Ring signal too weak: \(rssi) (need >= \(minRssi)). Skipping sync.")
                return
            }
            log("✅ Signal OK: \(rssi)")
        }
        
        var connected = false
        
        // Try multiple connection attempts
        for attempt in 1...maxRetries {
            if attempt > 1 {
                log("🔄 Retry attempt \(attempt)/\(maxRetries)...")
            }
            
            // Try to connect to saved ring first
            if let ringId = savedRingId {
                log("📡 Looking for saved ring...")
                let peripherals = centralManager.retrievePeripherals(withIdentifiers: [ringId])
                if let p = peripherals.first {
                    log("✅ Found saved ring, connecting...")
                    peripheral = p
                    peripheral?.delegate = self
                    centralManager.connect(p, options: nil)
                    
                    // Wait for connection with incremental checks
                    let deadline = Date(timeIntervalSinceNow: 15)
                    while Date() < deadline && rxCharacteristic == nil {
                        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
                    }
                    
                    if rxCharacteristic != nil {
                        connected = true
                        break
                    } else {
                        log("⚠️ Direct connect failed, will scan...")
                        if let p = peripheral {
                            centralManager.cancelPeripheralConnection(p)
                        }
                        peripheral = nil
                    }
                }
            }
            
            // Fall back to scanning
            if scanAndConnect() {
                connected = true
                break
            }
            
            // Brief pause between retries
            if attempt < maxRetries {
                log("⏳ Waiting 3 seconds before retry...")
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 3))
            }
        }
        
        if connected && rxCharacteristic != nil {
            log("✅ Connected! Syncing...")
            
            // Sync time first (important for step tracking)
            log("⏰ Syncing time...")
            _ = sendPacket(ColmiPacket.setTimePacket(), waitTime: 0.5)
            
            syncData()
            if historyDays > 0 {
                syncHistory(days: historyDays)
            }
        } else {
            log("❌ Could not find/connect to ring after \(maxRetries) attempts")
        }
    }
    
    /// Quick scan to find ring and get RSSI (returns -100 if not found)
    private func scanForRing() -> Int {
        lastSeenRssi = -100
        
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        let deadline = Date(timeIntervalSinceNow: min(scanTimeout, 15))
        while Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            if lastSeenRssi > -100 {
                break  // Found it
            }
        }
        
        centralManager.stopScan()
        return lastSeenRssi
    }
    
    private func scanAndConnect() -> Bool {
        // Reset state
        peripheral = nil
        rxCharacteristic = nil
        
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true  // See the ring even if already seen
        ])
        log("📡 Scanning for \(Int(scanTimeout)) seconds...")
        
        let deadline = Date(timeIntervalSinceNow: scanTimeout)
        while Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            
            // Check if we connected during scan
            if rxCharacteristic != nil {
                centralManager.stopScan()
                return true
            }
        }
        
        centralManager.stopScan()
        return rxCharacteristic != nil
    }
    
    private func syncData() {
        // Get battery
        if let battery = sendCommand(0x03) {
            let level = Int(battery[1])
            log("🔋 Battery: \(level)%")
            saveLatest(battery: level)
        }
        
        // Get real-time HR - wait for valid reading
        log("❤️ Measuring heart rate (up to 30s)...")
        let hrStart = Data([0x69, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6B])
        if let hr = waitForValidReading(startPacket: hrStart, type: 0x01, timeout: 30) {
            log("❤️ Heart Rate: \(hr) BPM")
            saveLatest(heartRate: hr)
        } else {
            log("⚠️ Could not get heart rate - ensure ring is snug on finger")
        }
        // Stop HR
        let hrStop = Data([0x6A, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6B])
        _ = sendPacket(hrStop, waitTime: 1)
        
        // Brief pause between measurements
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        
        // Get real-time SpO2 - wait for valid reading
        log("🫁 Measuring SpO2 (up to 30s)...")
        let spo2Start = Data([0x69, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6D])
        if let spo2 = waitForValidReading(startPacket: spo2Start, type: 0x03, timeout: 30) {
            log("🫁 SpO2: \(spo2)%")
            saveLatest(spO2: spo2)
        } else {
            log("⚠️ Could not get SpO2 - ensure ring is snug on finger")
        }
        // Stop SpO2
        let spo2Stop = Data([0x6A, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6D])
        _ = sendPacket(spo2Stop, waitTime: 1)
        
        // Enable continuous monitoring if requested
        if enableMonitoringInterval > 0 {
            log("⚙️ Enabling continuous HR monitoring (every \(enableMonitoringInterval) min)...")
            enableContinuousMonitoring(intervalMinutes: enableMonitoringInterval)
        }
        
        log("✅ Sync complete!")
    }
    
    private func enableContinuousMonitoring(intervalMinutes: Int) {
        // HR Log Settings command 0x16
        // Write: [0x16, 0x02, enabled (1=on), interval_minutes, ...]
        var packet = Data(count: 16)
        packet[0] = 0x16  // Command
        packet[1] = 0x02  // Write subtype
        packet[2] = 0x01  // Enabled = true
        packet[3] = UInt8(intervalMinutes)
        
        // Calculate checksum
        var checksum: UInt8 = 0
        for i in 0..<15 {
            checksum = checksum &+ packet[i]
        }
        packet[15] = checksum
        
        if let response = sendPacket(packet, waitTime: 2, expectedCmd: 0x16) {
            if response[2] == 0x01 {
                log("   ✅ HR monitoring enabled")
            } else {
                log("   ⚠️ HR monitoring disabled in response")
            }
        } else {
            log("   ⚠️ No response to HR settings command")
        }
        
        // Enable stress monitoring (0x36)
        enableHealthFeature(cmd: 0x36, name: "Stress")
        
        // Enable HRV monitoring (0x38)
        enableHealthFeature(cmd: 0x38, name: "HRV")
    }
    
    private func enableHealthFeature(cmd: UInt8, name: String) {
        var packet = Data(count: 16)
        packet[0] = cmd
        packet[1] = 0x02  // Write subtype
        packet[2] = 0x01  // Enabled
        
        var checksum: UInt8 = 0
        for i in 0..<15 {
            checksum = checksum &+ packet[i]
        }
        packet[15] = checksum
        
        if let response = sendPacket(packet, waitTime: 2, expectedCmd: cmd) {
            if response[2] == 0x01 {
                log("   ✅ \(name) monitoring enabled")
            } else {
                log("   ⚠️ \(name) monitoring disabled in response")
            }
        } else {
            log("   ⚠️ No response to \(name) settings")
        }
    }
    
    private func syncHistory(days: Int) {
        log("📅 Syncing \(days) days of history...")
        
        let calendar = Calendar.current
        let today = Date()
        let hrParser = HeartRateLogParser()
        let activityParser = ActivityParser()
        let spo2Parser = SpO2LogParser()
        let stressParser = StressLogParser()
        let hrvParser = HRVLogParser()
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = ISO8601DateFormatter().string(from: date).prefix(10)
            
            log("📊 Day \(dateStr):")
            
            // 1. HR Log
            let hrRequestPacket = HeartRateLogParser.requestPacket(for: date)
            hrParser.reset()
            
            var hrLog: HeartRateLog?
            var deadline = Date(timeIntervalSinceNow: 5)
            _ = sendPacket(hrRequestPacket, waitTime: 0.5)
            
            while Date() < deadline && hrLog == nil {
                if let response = waitForResponse(timeout: 1) {
                    if let result = hrParser.parse(response) {
                        hrLog = result
                    }
                } else {
                    break
                }
            }
            
            if let hrLog = hrLog {
                log("   ❤️ HR: \(hrLog.validReadings.count) readings")
                saveHRLog(hrLog, dateStr: String(dateStr))
            } else {
                log("   ❤️ HR: no data")
            }
            
            // 2. Activity/Steps
            let activityPacket = ActivityParser.requestPacket(dayOffset: dayOffset)
            activityParser.reset()
            
            var activity: DailyActivity?
            deadline = Date(timeIntervalSinceNow: 5)
            _ = sendPacket(activityPacket, waitTime: 0.5)
            
            while Date() < deadline && activity == nil {
                if let response = waitForResponse(timeout: 1) {
                    if let result = activityParser.parse(response) {
                        activity = result
                    }
                } else {
                    break
                }
            }
            
            if let activity = activity {
                log("   🚶 Steps: \(activity.totalSteps), Cal: \(activity.totalCalories)")
                saveActivity(activity, dateStr: String(dateStr))
            } else {
                log("   🚶 Steps: no data")
            }
            
            // 3. SpO2 Log
            let spo2Packet = SpO2LogParser.requestPacket(for: date)
            spo2Parser.reset()
            
            var spo2Log: SpO2Log?
            deadline = Date(timeIntervalSinceNow: 5)
            _ = sendPacket(spo2Packet, waitTime: 0.5)
            
            while Date() < deadline && spo2Log == nil {
                if let response = waitForResponse(timeout: 1) {
                    if let result = spo2Parser.parse(response) {
                        spo2Log = result
                    }
                } else {
                    break
                }
            }
            
            if let spo2Log = spo2Log {
                log("   🫁 SpO2: \(spo2Log.validReadings.count) readings")
                saveSpO2Log(spo2Log, dateStr: String(dateStr))
            } else {
                log("   🫁 SpO2: no data")
            }
            
            // 4. Stress Log
            let stressPacket = StressLogParser.requestPacket(dayOffset: dayOffset)
                stressParser.reset()
                
                var stressLog: StressLog?
                deadline = Date(timeIntervalSinceNow: 5)
                _ = sendPacket(stressPacket, waitTime: 0.5)
                
                while Date() < deadline && stressLog == nil {
                    if let response = waitForResponse(timeout: 1) {
                        if let result = stressParser.parse(response) {
                            stressLog = result
                        }
                    } else {
                        break
                    }
                }
                
                if let stressLog = stressLog {
                    log("   😰 Stress: \(stressLog.validReadings.count) readings")
                    saveStressLog(stressLog, dateStr: String(dateStr))
                } else {
                    log("   😰 Stress: no data")
                }
                
                // 5. HRV Log
                let hrvPacket = HRVLogParser.requestPacket(dayOffset: dayOffset)
                hrvParser.reset()
                
                var hrvLog: HRVLog?
                deadline = Date(timeIntervalSinceNow: 5)
                _ = sendPacket(hrvPacket, waitTime: 0.5)
                
                while Date() < deadline && hrvLog == nil {
                    if let response = waitForResponse(timeout: 1) {
                        if let result = hrvParser.parse(response) {
                            hrvLog = result
                        }
                    } else {
                        break
                    }
                }
                
            if let hrvLog = hrvLog {
                log("   💓 HRV: \(hrvLog.validReadings.count) readings")
                saveHRVLog(hrvLog, dateStr: String(dateStr))
            } else {
                log("   💓 HRV: no data")
            }
            
            // Small delay between days
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        }
        
        log("📅 History sync complete!")
        
        // Disconnect
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
    }
    
    private func waitForResponse(timeout: TimeInterval) -> Data? {
        guard let rx = rxCharacteristic else { return nil }
        
        var responseData: Data?
        let deadline = Date(timeIntervalSinceNow: timeout)
        
        pendingResponse = { data in
            responseData = data
        }
        
        peripheral?.setNotifyValue(true, for: rx)
        
        while Date() < deadline && responseData == nil {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        
        return responseData
    }
    
    private func saveHRLog(_ log: HeartRateLog, dateStr: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let file = dir.appendingPathComponent("hr-\(dateStr).json")
        
        let data: [String: Any] = [
            "date": dateStr,
            "readings": log.readings,
            "validCount": log.validReadings.count
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: file)
        }
    }
    
    private func saveActivity(_ activity: DailyActivity, dateStr: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let file = dir.appendingPathComponent("activity-\(dateStr).json")
        
        let details = activity.details.map { detail -> [String: Any] in
            return [
                "timestamp": ISO8601DateFormatter().string(from: detail.timestamp),
                "steps": detail.steps,
                "calories": detail.calories,
                "distance": detail.distance
            ]
        }
        
        let data: [String: Any] = [
            "date": dateStr,
            "totalSteps": activity.totalSteps,
            "totalCalories": activity.totalCalories,
            "totalDistance": activity.totalDistance,
            "details": details
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: file)
        }
    }
    
    private func saveSpO2Log(_ log: SpO2Log, dateStr: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let file = dir.appendingPathComponent("spo2-\(dateStr).json")
        
        let data: [String: Any] = [
            "date": dateStr,
            "readings": log.readings,
            "validCount": log.validReadings.count
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: file)
        }
    }
    
    private func saveStressLog(_ log: StressLog, dateStr: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let file = dir.appendingPathComponent("stress-\(dateStr).json")
        
        let data: [String: Any] = [
            "date": dateStr,
            "readings": log.readings,
            "validCount": log.validReadings.count
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: file)
        }
    }
    
    private func saveHRVLog(_ log: HRVLog, dateStr: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let file = dir.appendingPathComponent("hrv-\(dateStr).json")
        
        let data: [String: Any] = [
            "date": dateStr,
            "readings": log.readings,
            "validCount": log.validReadings.count
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? jsonData.write(to: file)
        }
    }
    
    /// Wait for a valid (non-zero) reading from the ring
    private func waitForValidReading(startPacket: Data, type: UInt8, timeout: TimeInterval) -> Int? {
        guard let rx = rxCharacteristic else { return nil }
        
        var validValue: Int?
        let deadline = Date(timeIntervalSinceNow: timeout)
        
        pendingResponse = { data in
            guard let data = data, data.count >= 4 else { return }
            // Check it's a real-time reading response (0x69) for our type
            if data[0] == 0x69 && data[1] == type {
                let status = data[2]
                let value = Int(data[3])
                if status == 0 && value > 0 {
                    validValue = value
                }
            }
        }
        
        // Send start command
        peripheral?.writeValue(startPacket, for: rx, type: .withoutResponse)
        
        // Poll until we get a valid value or timeout
        while Date() < deadline && validValue == nil {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        
        pendingResponse = nil
        return validValue
    }
    
    private func sendCommand(_ cmd: UInt8) -> Data? {
        var packet = Data(count: 16)
        packet[0] = cmd
        packet[15] = cmd // Simple checksum for single-byte commands
        return sendPacket(packet, waitTime: 2, expectedCmd: cmd)
    }
    
    private func sendPacket(_ packet: Data, waitTime: TimeInterval, expectedCmd: UInt8? = nil) -> Data? {
        guard let rx = rxCharacteristic else { return nil }
        
        var response: Data?
        pendingResponse = { data in
            guard let data = data else { return }
            // If we expect a specific command response, only capture that one
            if let expected = expectedCmd {
                if data[0] == expected && response == nil {
                    response = data
                }
            } else if response == nil {
                response = data
            }
        }
        
        peripheral?.writeValue(packet, for: rx, type: .withoutResponse)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: waitTime))
        
        pendingResponse = nil
        return response
    }
    
    private func loadSavedRing() {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colmisync/paired_ring.json")
        
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONDecoder().decode([String: String].self, from: data),
              let idString = json["id"],
              let uuid = UUID(uuidString: idString) else {
            return
        }
        savedRingId = uuid
        savedRingName = json["name"]
        log("📋 Loaded saved ring: \(savedRingName ?? "Unknown")")
    }
    
    private func saveRing(id: UUID, name: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colmisync")
        let file = dir.appendingPathComponent("paired_ring.json")
        
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = ["id": id.uuidString, "name": name]
        if let data = try? JSONEncoder().encode(json) {
            try? data.write(to: file)
        }
    }
    
    /// Parse CLI arguments
    nonisolated static func parseArgs(_ args: [String]) -> (scanTime: Int, retries: Int, historyDays: Int, enableMonitoring: Int, minRssi: Int, scanOnly: Bool) {
        var scanTime = 30
        var retries = 3
        var historyDays = 0  // 0 = no history sync
        var enableMonitoring = 0  // 0 = don't change, >0 = enable with interval
        var minRssi = -100  // minimum RSSI to attempt connection (-100 = any signal)
        var scanOnly = false  // just scan, don't sync
        
        var i = 0
        while i < args.count {
            if args[i] == "--scan-time" && i + 1 < args.count {
                scanTime = Int(args[i + 1]) ?? 30
                i += 2
            } else if args[i] == "--retries" && i + 1 < args.count {
                retries = Int(args[i + 1]) ?? 3
                i += 2
            } else if args[i] == "--history" {
                // --history OR --history 7
                if i + 1 < args.count, let days = Int(args[i + 1]), days > 0 {
                    historyDays = days
                    i += 2
                } else {
                    historyDays = 7  // default 7 days
                    i += 1
                }
            } else if args[i] == "--enable-monitoring" {
                // --enable-monitoring OR --enable-monitoring 5
                if i + 1 < args.count, let interval = Int(args[i + 1]), interval > 0 {
                    enableMonitoring = interval
                    i += 2
                } else {
                    enableMonitoring = 5  // default 5 minutes
                    i += 1
                }
            } else if args[i] == "--min-rssi" && i + 1 < args.count {
                minRssi = Int(args[i + 1]) ?? -75
                i += 2
            } else if args[i] == "--scan-only" {
                scanOnly = true
                i += 1
            } else {
                i += 1
            }
        }
        
        return (scanTime, retries, historyDays, enableMonitoring, minRssi, scanOnly)
    }
    
    private func saveLatest(heartRate: Int? = nil, spO2: Int? = nil, battery: Int? = nil) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let file = dir.appendingPathComponent("latest.json")
        var latest: [String: Any] = [:]
        
        if let existing = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
            latest = json
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        
        if let hr = heartRate {
            latest["heartRate"] = hr
            latest["heartRateTime"] = now
        }
        if let spo2 = spO2 {
            latest["spO2"] = spo2
            latest["spO2Time"] = now
        }
        if let bat = battery {
            latest["battery"] = bat
            latest["batteryTime"] = now
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: latest, options: .prettyPrinted) {
            try? data.write(to: file)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // State handled in run()
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let rssiValue = RSSI.intValue
        
        Task { @MainActor in
            // Match by UUID OR by saved name (UUIDs can change between sessions on macOS)
            let matchesSavedId = self.savedRingId == peripheral.identifier
            let matchesSavedName = self.savedRingName != nil && name == self.savedRingName
            let isOurRing = matchesSavedId || matchesSavedName
            
            if isOurRing {
                // Update saved UUID if it changed (name matched but ID didn't)
                if matchesSavedName && !matchesSavedId {
                    self.savedRingId = peripheral.identifier
                    self.saveRing(id: peripheral.identifier, name: name)
                    log("🔄 Updated ring UUID (was changed by system)")
                }
                
                // Save RSSI for signal strength checking
                self.lastSeenRssi = rssiValue
                
                // In scan-only mode, just record RSSI and stop
                if self.scanOnly {
                    central.stopScan()
                    return
                }
                
                log("📱 Found our ring: \(name) (RSSI: \(rssiValue))")
                central.stopScan()
                self.peripheral = peripheral
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
            } else if name.hasPrefix("R0") || name.lowercased().contains("colmi") {
                // Only connect to other rings if we don't have a saved one
                if self.savedRingId == nil && self.peripheral == nil {
                    self.lastSeenRssi = rssiValue
                    
                    if self.scanOnly {
                        central.stopScan()
                        return
                    }
                    
                    log("📱 Found ring: \(name) (RSSI: \(rssiValue))")
                    central.stopScan()
                    self.peripheral = peripheral
                    peripheral.delegate = self
                    central.connect(peripheral, options: nil)
                }
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("🔗 Connected, discovering services...")
        peripheral.discoverServices([CBUUID(string: "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E")])
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("❌ Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }
    
    // MARK: - CBPeripheralDelegate
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first else { return }
        peripheral.discoverCharacteristics([
            CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"),
            CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
        ], for: service)
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                if char.uuid == CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") {
                    self.rxCharacteristic = char
                } else if char.uuid == CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            log("✅ Characteristics ready")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            self.pendingResponse?(data)
        }
    }
}
