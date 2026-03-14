import Foundation
import CoreBluetooth

// Simple CLI sync tool - runs once, syncs, exits
// Usage: swift run ColmiSync --cli

@MainActor
class CLISync: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    private var savedRingId: UUID?
    
    private var pendingResponse: ((Data?) -> Void)?
    private let semaphore = DispatchSemaphore(value: 0)
    
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
        
        // Try to connect to saved ring
        if let ringId = savedRingId {
            print("📡 Looking for saved ring...")
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [ringId])
            if let p = peripherals.first {
                print("✅ Found saved ring, connecting...")
                peripheral = p
                peripheral?.delegate = self
                centralManager.connect(p, options: nil)
                
                // Wait for connection
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 10))
                
                if rxCharacteristic != nil {
                    print("✅ Connected! Syncing...")
                    syncData()
                } else {
                    print("❌ Connection failed - ring might be asleep")
                    // Try scanning
                    scanAndConnect()
                }
            } else {
                print("⚠️ Saved ring not found, scanning...")
                scanAndConnect()
            }
        } else {
            print("⚠️ No saved ring, scanning...")
            scanAndConnect()
        }
    }
    
    private func scanAndConnect() {
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        print("📡 Scanning for 10 seconds...")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 10))
        centralManager.stopScan()
        
        if peripheral != nil && rxCharacteristic != nil {
            print("✅ Connected! Syncing...")
            syncData()
        } else {
            print("❌ Could not find/connect to ring")
        }
    }
    
    private func syncData() {
        // Get battery
        if let battery = sendCommand(0x03) {
            let level = Int(battery[1])
            print("🔋 Battery: \(level)%")
        }
        
        // Get real-time HR
        let hrStart = Data([0x69, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6B])
        if let hrResponse = sendPacket(hrStart, waitTime: 15) {
            if hrResponse[0] == 0x69 && hrResponse[2] == 0 {
                let hr = Int(hrResponse[3])
                print("❤️ Heart Rate: \(hr) BPM")
                saveLatest(heartRate: hr)
            }
        }
        // Stop HR
        let hrStop = Data([0x6A, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6B])
        _ = sendPacket(hrStop, waitTime: 1)
        
        // Get real-time SpO2
        let spo2Start = Data([0x69, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6D])
        if let spo2Response = sendPacket(spo2Start, waitTime: 15) {
            if spo2Response[0] == 0x69 && spo2Response[2] == 0 {
                let spo2 = Int(spo2Response[3])
                print("🫁 SpO2: \(spo2)%")
                saveLatest(spO2: spo2)
            }
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
    
    private func sendCommand(_ cmd: UInt8) -> Data? {
        var packet = Data(count: 16)
        packet[0] = cmd
        packet[15] = cmd // Simple checksum for single-byte commands
        return sendPacket(packet, waitTime: 2)
    }
    
    private func sendPacket(_ packet: Data, waitTime: TimeInterval) -> Data? {
        guard let rx = rxCharacteristic else { return nil }
        
        var response: Data?
        pendingResponse = { data in
            response = data
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
        print("📋 Loaded saved ring: \(json["name"] ?? "Unknown")")
    }
    
    private func saveLatest(heartRate: Int? = nil, spO2: Int? = nil) {
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
        
        if let data = try? JSONSerialization.data(withJSONObject: latest, options: .prettyPrinted) {
            try? data.write(to: file)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // State handled in run()
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        if name.hasPrefix("R0") || name.lowercased().contains("colmi") {
            Task { @MainActor in
                print("📱 Found ring: \(name)")
                central.stopScan()
                self.peripheral = peripheral
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
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
