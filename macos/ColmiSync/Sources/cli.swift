import Foundation
import CoreBluetooth

// Simple CLI sync tool - runs once, syncs, exits
// Usage: swift run ColmiSync --cli [--scan-time 30]

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
    
    override init() {
        super.init()
        loadSavedRing()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        print("🔄 ColmiSync CLI - Starting...")
        
        // Wait for Bluetooth to be ready
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        
        guard centralManager.state == .poweredOn else {
            print("❌ Bluetooth not available")
            return
        }
        
        var connected = false
        
        // Try multiple connection attempts
        for attempt in 1...maxRetries {
            if attempt > 1 {
                print("🔄 Retry attempt \(attempt)/\(maxRetries)...")
            }
            
            // Try to connect to saved ring first
            if let ringId = savedRingId {
                print("📡 Looking for saved ring...")
                let peripherals = centralManager.retrievePeripherals(withIdentifiers: [ringId])
                if let p = peripherals.first {
                    print("✅ Found saved ring, connecting...")
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
                        print("⚠️ Direct connect failed, will scan...")
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
                print("⏳ Waiting 3 seconds before retry...")
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 3))
            }
        }
        
        if connected && rxCharacteristic != nil {
            print("✅ Connected! Syncing...")
            syncData()
        } else {
            print("❌ Could not find/connect to ring after \(maxRetries) attempts")
        }
    }
    
    private func scanAndConnect() -> Bool {
        // Reset state
        peripheral = nil
        rxCharacteristic = nil
        
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true  // See the ring even if already seen
        ])
        print("📡 Scanning for \(Int(scanTimeout)) seconds...")
        
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
            print("🔋 Battery: \(level)%")
            saveLatest(battery: level)
        }
        
        // Get real-time HR - wait for valid reading
        print("❤️ Measuring heart rate (up to 30s)...")
        let hrStart = Data([0x69, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6B])
        if let hr = waitForValidReading(startPacket: hrStart, type: 0x01, timeout: 30) {
            print("❤️ Heart Rate: \(hr) BPM")
            saveLatest(heartRate: hr)
        } else {
            print("⚠️ Could not get heart rate - ensure ring is snug on finger")
        }
        // Stop HR
        let hrStop = Data([0x6A, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6B])
        _ = sendPacket(hrStop, waitTime: 1)
        
        // Brief pause between measurements
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        
        // Get real-time SpO2 - wait for valid reading
        print("🫁 Measuring SpO2 (up to 30s)...")
        let spo2Start = Data([0x69, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6D])
        if let spo2 = waitForValidReading(startPacket: spo2Start, type: 0x03, timeout: 30) {
            print("🫁 SpO2: \(spo2)%")
            saveLatest(spO2: spo2)
        } else {
            print("⚠️ Could not get SpO2 - ensure ring is snug on finger")
        }
        // Stop SpO2
        let spo2Stop = Data([0x6A, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6D])
        _ = sendPacket(spo2Stop, waitTime: 1)
        
        print("✅ Sync complete!")
        
        // Disconnect
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
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
        print("📋 Loaded saved ring: \(savedRingName ?? "Unknown")")
    }
    
    /// Parse CLI arguments
    static func parseArgs(_ args: [String]) -> (scanTime: Int, retries: Int) {
        var scanTime = 30
        var retries = 3
        
        var i = 0
        while i < args.count {
            if args[i] == "--scan-time" && i + 1 < args.count {
                scanTime = Int(args[i + 1]) ?? 30
                i += 2
            } else if args[i] == "--retries" && i + 1 < args.count {
                retries = Int(args[i + 1]) ?? 3
                i += 2
            } else {
                i += 1
            }
        }
        
        return (scanTime, retries)
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
        
        // Prioritize our saved ring if we have one
        let isSavedRing = Task { @MainActor in
            return self.savedRingId == peripheral.identifier
        }
        
        Task { @MainActor in
            let saved = await isSavedRing.value
            
            if saved {
                print("📱 Found our ring: \(name) (RSSI: \(RSSI))")
                central.stopScan()
                self.peripheral = peripheral
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
            } else if name.hasPrefix("R0") || name.lowercased().contains("colmi") {
                // Only connect to other rings if we don't have a saved one
                if self.savedRingId == nil && self.peripheral == nil {
                    print("📱 Found ring: \(name) (RSSI: \(RSSI))")
                    central.stopScan()
                    self.peripheral = peripheral
                    peripheral.delegate = self
                    central.connect(peripheral, options: nil)
                }
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("🔗 Connected, discovering services...")
        peripheral.discoverServices([CBUUID(string: "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E")])
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ Failed to connect: \(error?.localizedDescription ?? "unknown")")
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
            print("✅ Characteristics ready")
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            self.pendingResponse?(data)
        }
    }
}
