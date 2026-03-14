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
    @Published var todaySteps: Int?
    @Published var todayCalories: Int?
    
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    
    private let logger = Logger(subsystem: "com.colmisync", category: "BLE")
    
    // Persistence keys
    private let savedRingIdKey = "savedRingIdentifier"
    private let savedRingNameKey = "savedRingName"
    
    // Parsers
    private let hrLogParser = HeartRateLogParser()
    private let activityParser = ActivityParser()
    private let spo2LogParser = SpO2LogParser()
    
    // Continuations for async/await
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var batteryContinuation: CheckedContinuation<BatteryInfo, Error>?
    private var realTimeContinuation: CheckedContinuation<Int, Error>?
    private var hrLogContinuation: CheckedContinuation<HeartRateLog?, Error>?
    private var activityContinuation: CheckedContinuation<DailyActivity?, Error>?
    private var spo2LogContinuation: CheckedContinuation<SpO2Log?, Error>?
    
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
        
        // Scan for ALL BLE devices - rings don't always advertise service UUIDs
        centralManager.scanForPeripherals(withServices: nil, options: [
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
        
        // Save for auto-reconnect
        UserDefaults.standard.set(ring.id.uuidString, forKey: savedRingIdKey)
        UserDefaults.standard.set(ring.name, forKey: savedRingNameKey)
        
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
    
    /// Try to reconnect to previously paired ring
    func tryAutoReconnect() {
        guard let savedIdString = UserDefaults.standard.string(forKey: savedRingIdKey),
              let savedId = UUID(uuidString: savedIdString) else {
            logger.info("No saved ring to reconnect")
            return
        }
        
        let savedName = UserDefaults.standard.string(forKey: savedRingNameKey) ?? "Saved Ring"
        logger.info("Attempting auto-reconnect to \(savedName)")
        
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [savedId])
        
        if let peripheral = peripherals.first {
            let ring = DiscoveredRing(
                id: peripheral.identifier,
                name: savedName,
                rssi: 0,
                peripheral: peripheral
            )
            
            Task {
                do {
                    try await connect(to: ring)
                    logger.info("Auto-reconnected to \(savedName)")
                } catch {
                    logger.error("Auto-reconnect failed: \(error.localizedDescription)")
                    // Fall back to scanning
                    startScanning()
                }
            }
        } else {
            logger.info("Saved ring not found, starting scan")
            startScanning()
        }
    }
    
    /// Forget saved ring
    func forgetRing() {
        UserDefaults.standard.removeObject(forKey: savedRingIdKey)
        UserDefaults.standard.removeObject(forKey: savedRingNameKey)
        disconnect()
        logger.info("Forgot saved ring")
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
                
                // Save to store
                try? await DataStore.shared.saveLatestReading(heartRate: hr, battery: batteryLevel)
            }
            
            // Get today's steps/activity
            if let activity = try await getActivity(dayOffset: 0) {
                todaySteps = activity.totalSteps
                todayCalories = activity.totalCalories
                logger.info("Today: \(activity.totalSteps) steps, \(activity.totalCalories) cal")
                
                // Save to store
                try? await DataStore.shared.saveActivity(activity)
            }
            
            // Get today's HR log (historical readings)
            if let hrLog = try await getHeartRateLog(for: Date()) {
                logger.info("HR log: \(hrLog.validReadings.count) readings")
                try? await DataStore.shared.saveHeartRateLog(hrLog)
            }
            
            lastSyncDate = Date()
            
        } catch {
            logger.error("Sync error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
    
    /// Sync all data for a date range (for initial sync or catch-up)
    func syncHistory(days: Int = 7) async {
        guard isConnected else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        let calendar = Calendar.current
        let today = Date()
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            do {
                // HR log for this day
                if let hrLog = try await getHeartRateLog(for: date) {
                    logger.info("HR log \(date): \(hrLog.validReadings.count) readings")
                    try? await DataStore.shared.saveHeartRateLog(hrLog)
                }
                
                // Activity for this day
                if let activity = try await getActivity(dayOffset: dayOffset) {
                    logger.info("Activity \(date): \(activity.totalSteps) steps")
                    try? await DataStore.shared.saveActivity(activity)
                }
                
                // SpO2 log for this day
                if let spo2Log = try await getSpO2Log(for: date) {
                    logger.info("SpO2 log \(date): \(spo2Log.validReadings.count) readings")
                    try? await DataStore.shared.saveSpO2Log(spo2Log)
                }
                
            } catch {
                logger.error("Error syncing \(date): \(error.localizedDescription)")
            }
        }
        
        lastSyncDate = Date()
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
    
    private func getHeartRateLog(for date: Date) async throws -> HeartRateLog? {
        hrLogParser.reset()
        await sendPacket(HeartRateLogParser.requestPacket(for: date))
        
        return try await withCheckedThrowingContinuation { continuation in
            self.hrLogContinuation = continuation
            
            // Timeout after 10 seconds
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                if self.hrLogContinuation != nil {
                    self.hrLogContinuation?.resume(returning: nil)
                    self.hrLogContinuation = nil
                }
            }
        }
    }
    
    private func getActivity(dayOffset: Int) async throws -> DailyActivity? {
        activityParser.reset()
        await sendPacket(ActivityParser.requestPacket(dayOffset: dayOffset))
        
        return try await withCheckedThrowingContinuation { continuation in
            self.activityContinuation = continuation
            
            // Timeout after 10 seconds
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                if self.activityContinuation != nil {
                    self.activityContinuation?.resume(returning: nil)
                    self.activityContinuation = nil
                }
            }
        }
    }
    
    private func getSpO2Log(for date: Date) async throws -> SpO2Log? {
        spo2LogParser.reset()
        await sendPacket(SpO2LogParser.requestPacket(for: date))
        
        return try await withCheckedThrowingContinuation { continuation in
            self.spo2LogContinuation = continuation
            
            // Timeout after 10 seconds
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                if self.spo2LogContinuation != nil {
                    self.spo2LogContinuation?.resume(returning: nil)
                    self.spo2LogContinuation = nil
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
                hrLogContinuation?.resume(returning: log)
                hrLogContinuation = nil
            }
            
        case .readActivity:
            if let activity = activityParser.parse(data) {
                logger.info("Received activity: \(activity.totalSteps) steps")
                Task { @MainActor in
                    self.todaySteps = activity.totalSteps
                    self.todayCalories = activity.totalCalories
                }
                activityContinuation?.resume(returning: activity)
                activityContinuation = nil
            }
            
        case .readSpO2Log:
            if let log = spo2LogParser.parse(data) {
                logger.info("Received SpO2 log: \(log.validReadings.count) readings")
                spo2LogContinuation?.resume(returning: log)
                spo2LogContinuation = nil
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
                // Try to reconnect to saved ring
                self.tryAutoReconnect()
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
