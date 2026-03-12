import Foundation
import CoreBluetooth
import Combine
import os

/// Represents a discovered Colmi ring
struct DiscoveredRing: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
    
    static func == (lhs: DiscoveredRing, rhs: DiscoveredRing) -> Bool {
        lhs.id == rhs.id
    }
}

/// Main BLE manager for Colmi ring communication
@MainActor
class BLEManager: NSObject, ObservableObject {
    // MARK: - Published State
    
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var discoveredRings: [DiscoveredRing] = []
    @Published var connectedRing: DiscoveredRing?
    
    @Published var batteryLevel: Int?
    @Published var lastHeartRate: Int?
    @Published var lastSpO2: Int?
    @Published var lastSyncDate: Date?
    
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    
    private let logger = Logger(subsystem: "com.colmisync", category: "BLE")
    
    // Parsers
    private let hrLogParser = HeartRateLogParser()
    
    // Continuations for async/await
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var batteryContinuation: CheckedContinuation<BatteryInfo, Error>?
    private var realTimeContinuation: CheckedContinuation<Int, Error>?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            errorMessage = "Bluetooth is not available"
            return
        }
        
        discoveredRings.removeAll()
        isScanning = true
        
        let serviceUUIDs = [CBUUID(string: ColmiUUID.service)]
        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        logger.info("Started scanning for Colmi rings")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        logger.info("Stopped scanning")
    }
    
    func connect(to ring: DiscoveredRing) async throws {
        stopScanning()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionContinuation = continuation
            self.centralManager.connect(ring.peripheral, options: nil)
        }
        
        connectedRing = ring
        peripheral = ring.peripheral
        isConnected = true
        
        logger.info("Connected to \(ring.name)")
        
        // Initial setup after connection
        await initialSync()
    }
    
    func disconnect() {
        guard let peripheral = peripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        
        self.peripheral = nil
        self.rxCharacteristic = nil
        self.txCharacteristic = nil
        self.connectedRing = nil
        self.isConnected = false
        
        logger.info("Disconnected")
    }
    
    func syncData() async {
        guard isConnected else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Get battery
            if let battery = try await getBattery() {
                batteryLevel = battery.level
                logger.info("Battery: \(battery.level)%, charging: \(battery.isCharging)")
            }
            
            // Get real-time heart rate
            if let hr = try await getRealTimeHeartRate() {
                lastHeartRate = hr
                logger.info("Heart rate: \(hr) BPM")
            }
            
            lastSyncDate = Date()
            
        } catch {
            logger.error("Sync error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
    
    func findRing() async {
        await sendPacket(ColmiPacket.findDevicePacket)
    }
    
    // MARK: - Private Methods
    
    private func initialSync() async {
        // Set time on ring
        await sendPacket(ColmiPacket.setTimePacket())
        
        // Get initial data
        await syncData()
    }
    
    private func getBattery() async throws -> BatteryInfo? {
        return try await withCheckedThrowingContinuation { continuation in
            self.batteryContinuation = continuation
            Task {
                await self.sendPacket(BatteryInfo.requestPacket)
            }
            
            // Timeout after 5 seconds
            Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                if self.batteryContinuation != nil {
                    self.batteryContinuation?.resume(throwing: BLEError.timeout)
                    self.batteryContinuation = nil
                }
            }
        }
    }
    
    private func getRealTimeHeartRate() async throws -> Int? {
        await sendPacket(RealTimeReading.startPacket(type: .heartRate))
        
        defer {
            Task {
                await self.sendPacket(RealTimeReading.stopPacket(type: .heartRate))
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.realTimeContinuation = continuation
            
            // Timeout after 30 seconds
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if self.realTimeContinuation != nil {
                    self.realTimeContinuation?.resume(throwing: BLEError.timeout)
                    self.realTimeContinuation = nil
                }
            }
        }
    }
    
    private func sendPacket(_ data: Data) async {
        guard let peripheral = peripheral,
              let characteristic = rxCharacteristic else {
            logger.error("Cannot send packet: not connected")
            return
        }
        
        logger.debug("Sending packet: \(data.hexString)")
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
    
    private func handleReceivedPacket(_ data: Data) {
        logger.debug("Received packet: \(data.hexString)")
        
        guard ColmiPacket.isValid(data) else {
            logger.warning("Invalid packet checksum")
            return
        }
        
        guard let command = ColmiPacket.commandType(data) else {
            logger.warning("Unknown command type")
            return
        }
        
        switch command {
        case .battery:
            if let battery = BatteryInfo.parse(data) {
                Task { @MainActor in
                    self.batteryLevel = battery.level
                }
                batteryContinuation?.resume(returning: battery)
                batteryContinuation = nil
            }
            
        case .realTimeHR, .realTimeSpO2:
            if let reading = RealTimeReading.parse(data), !reading.isError, reading.value > 0 {
                Task { @MainActor in
                    if reading.type == .heartRate {
                        self.lastHeartRate = reading.value
                    } else {
                        self.lastSpO2 = reading.value
                    }
                }
                realTimeContinuation?.resume(returning: reading.value)
                realTimeContinuation = nil
            }
            
        case .readHeartRate:
            if let log = hrLogParser.parse(data) {
                logger.info("Received HR log for \(log.date): \(log.validReadings.count) readings")
                // TODO: Store in database
            }
            
        default:
            logger.info("Unhandled command: \(String(describing: command))")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                logger.info("Bluetooth is powered on")
            case .poweredOff:
                logger.warning("Bluetooth is powered off")
                errorMessage = "Please turn on Bluetooth"
            case .unauthorized:
                logger.error("Bluetooth unauthorized")
                errorMessage = "Bluetooth access not authorized"
            case .unsupported:
                logger.error("Bluetooth not supported")
                errorMessage = "Bluetooth not supported on this device"
            default:
                break
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Ring"
            
            // Filter for Colmi rings (usually start with "R0" or "Colmi")
            guard name.hasPrefix("R0") || name.lowercased().contains("colmi") || name.lowercased().contains("ring") else {
                return
            }
            
            let ring = DiscoveredRing(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                peripheral: peripheral
            )
            
            if !discoveredRings.contains(ring) {
                discoveredRings.append(ring)
                logger.info("Discovered ring: \(name) (RSSI: \(RSSI))")
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: ColmiUUID.service)])
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionContinuation?.resume(throwing: error ?? BLEError.connectionFailed)
            connectionContinuation = nil
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.peripheral = nil
            self.rxCharacteristic = nil
            self.txCharacteristic = nil
            self.connectedRing = nil
            self.isConnected = false
            
            if let error = error {
                logger.error("Disconnected with error: \(error.localizedDescription)")
            } else {
                logger.info("Disconnected")
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            Task { @MainActor in
                connectionContinuation?.resume(throwing: error!)
                connectionContinuation = nil
            }
            return
        }
        
        if let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: ColmiUUID.service) }) {
            peripheral.discoverCharacteristics([
                CBUUID(string: ColmiUUID.rxCharacteristic),
                CBUUID(string: ColmiUUID.txCharacteristic)
            ], for: service)
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            Task { @MainActor in
                connectionContinuation?.resume(throwing: error!)
                connectionContinuation = nil
            }
            return
        }
        
        Task { @MainActor in
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == CBUUID(string: ColmiUUID.rxCharacteristic) {
                    rxCharacteristic = characteristic
                    logger.debug("Found RX characteristic")
                } else if characteristic.uuid == CBUUID(string: ColmiUUID.txCharacteristic) {
                    txCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    logger.debug("Found TX characteristic, subscribed to notifications")
                }
            }
            
            if rxCharacteristic != nil && txCharacteristic != nil {
                connectionContinuation?.resume()
                connectionContinuation = nil
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        
        Task { @MainActor in
            handleReceivedPacket(data)
        }
    }
}

// MARK: - Errors

enum BLEError: LocalizedError {
    case connectionFailed
    case timeout
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Failed to connect to ring"
        case .timeout: return "Operation timed out"
        case .notConnected: return "Not connected to ring"
        }
    }
}

// MARK: - Data Extension

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
