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
    @Published var hrLogSettings: HRLogSettings?
    
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    
    private let logger = Logger(subsystem: "com.colmisync", category: "BLE")
    
    // Background sync timer
    private var syncTimer: Timer?
    
    // Persistence
    private var savedRingFile: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colmisync")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("paired_ring.json")
    }
    
    // Parsers
    private let hrLogParser = HeartRateLogParser()
    private let activityParser = ActivityParser()
    private let spo2LogParser = SpO2LogParser()
    
    // Continuations for async/await
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var batteryContinuation: CheckedContinuation<BatteryInfo, Error>?
    private var hrContinuation: CheckedContinuation<Int, Error>?
    private var spo2Continuation: CheckedContinuation<Int, Error>?
    private var hrLogContinuation: CheckedContinuation<HeartRateLog?, Error>?
    private var activityContinuation: CheckedContinuation<DailyActivity?, Error>?
    private var spo2LogContinuation: CheckedContinuation<SpO2Log?, Error>?
    private var hrLogSettingsContinuation: CheckedContinuation<HRLogSettings?, Error>?
    
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
        saveRingToFile(id: ring.id.uuidString, name: ring.name)
        
        logger.info("Connected to \(ring.name)")
        
        // Initial setup after connection
        await initialSync()
    }
    
    func disconnect() {
        guard let peripheral = peripheral else { return }
        
        stopBackgroundSync()
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
        guard let (savedIdString, savedName) = loadRingFromFile(),
              let savedId = UUID(uuidString: savedIdString) else {
            logger.info("No saved ring to reconnect")
            return
        }
        
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
                    // Schedule retry
                    scheduleReconnectRetry()
                }
            }
        } else {
            logger.info("Saved ring not found nearby, starting scan")
            startScanning()
            // Schedule retry
            scheduleReconnectRetry()
        }
    }
    
    private var reconnectTimer: Timer?
    
    private func scheduleReconnectRetry() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isConnected else { 
                    self?.reconnectTimer?.invalidate()
                    return 
                }
                self.logger.info("Retry reconnect...")
                self.tryAutoReconnect()
            }
        }
    }
    
    /// Forget saved ring
    func forgetRing() {
        try? FileManager.default.removeItem(at: savedRingFile)
        disconnect()
        logger.info("Forgot saved ring")
    }
    
    // MARK: - File Persistence
    
    private func saveRingToFile(id: String, name: String) {
        let data: [String: String] = ["id": id, "name": name]
        if let json = try? JSONEncoder().encode(data) {
            try? json.write(to: savedRingFile)
            logger.info("Saved ring to \(self.savedRingFile.path)")
        }
    }
    
    private func loadRingFromFile() -> (id: String, name: String)? {
        guard let json = try? Data(contentsOf: savedRingFile),
              let data = try? JSONDecoder().decode([String: String].self, from: json),
              let id = data["id"],
              let name = data["name"] else {
            return nil
        }
        return (id, name)
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
            
            // Get HR log settings (continuous monitoring config)
            if let settings = try await getHRLogSettings() {
                hrLogSettings = settings
                logger.info("Continuous monitoring: \(settings.enabled ? "ON" : "OFF"), interval: \(settings.intervalMinutes)min")
            }
            
            // Get real-time heart rate
            if let hr = try await getRealTimeHeartRate() {
                lastHeartRate = hr
                logger.info("Heart rate: \(hr) BPM")
            }
            
            // Get real-time SpO2
            if let spo2 = try await getRealTimeSpO2() {
                lastSpO2 = spo2
                logger.info("SpO2: \(spo2)%")
            }
            
            // Save to store
            try? await DataStore.shared.saveLatestReading(heartRate: lastHeartRate, spO2: lastSpO2, battery: batteryLevel)
            
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
    
    /// Get current HR log (continuous monitoring) settings
    func getHRLogSettings() async throws -> HRLogSettings? {
        await sendPacket(HRLogSettings.readPacket)
        
        return try await withCheckedThrowingContinuation { continuation in
            self.hrLogSettingsContinuation = continuation
            
            // Timeout after 5 seconds
            Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                if self.hrLogSettingsContinuation != nil {
                    self.hrLogSettingsContinuation?.resume(returning: nil)
                    self.hrLogSettingsContinuation = nil
                }
            }
        }
    }
    
    /// Set HR log (continuous monitoring) settings
    /// - Parameters:
    ///   - enabled: Whether continuous monitoring is enabled
    ///   - intervalMinutes: Monitoring interval (5, 10, 15, 30, 60 typical)
    func setHRLogSettings(enabled: Bool, intervalMinutes: Int) async throws {
        let settings = HRLogSettings(enabled: enabled, intervalMinutes: intervalMinutes)
        await sendPacket(settings.writePacket())
        
        // Wait for response and update local state
        if let newSettings = try await getHRLogSettings() {
            hrLogSettings = newSettings
            logger.info("HR log settings updated: enabled=\(newSettings.enabled), interval=\(newSettings.intervalMinutes)min")
        }
    }
    
    /// Enable continuous HR monitoring with specified interval
    func enableContinuousMonitoring(intervalMinutes: Int = 5) async throws {
        try await setHRLogSettings(enabled: true, intervalMinutes: intervalMinutes)
    }
    
    /// Disable continuous HR monitoring
    func disableContinuousMonitoring() async throws {
        try await setHRLogSettings(enabled: false, intervalMinutes: 5)
    }
    
    // MARK: - Private Methods
    
    private func initialSync() async {
        // Set time on ring
        await sendPacket(ColmiPacket.setTimePacket())
        
        // Get current readings
        await syncData()
        
        // Pull historical data (last 7 days)
        await syncHistory(days: 7)
        
        // Start background sync timer (every 5 minutes)
        startBackgroundSync()
    }
    
    private func startBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncData()
            }
        }
        logger.info("Background sync started (every 5 minutes)")
    }
    
    private func stopBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        logger.info("Background sync stopped")
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
            self.hrContinuation = continuation
            
            // Timeout after 30 seconds
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if self.hrContinuation != nil {
                    self.hrContinuation?.resume(throwing: BLEError.timeout)
                    self.hrContinuation = nil
                }
            }
        }
    }
    
    private func getRealTimeSpO2() async throws -> Int? {
        await sendPacket(RealTimeReading.startPacket(type: .spO2))
        
        defer {
            Task {
                await self.sendPacket(RealTimeReading.stopPacket(type: .spO2))
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.spo2Continuation = continuation
            
            // Timeout after 30 seconds
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if self.spo2Continuation != nil {
                    self.spo2Continuation?.resume(throwing: BLEError.timeout)
                    self.spo2Continuation = nil
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
                        self.hrContinuation?.resume(returning: reading.value)
                        self.hrContinuation = nil
                    } else {
                        self.lastSpO2 = reading.value
                        self.spo2Continuation?.resume(returning: reading.value)
                        self.spo2Continuation = nil
                    }
                }
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
            
        case .hrLogSettings:
            if let settings = HRLogSettings.parse(data) {
                logger.info("HR log settings: enabled=\(settings.enabled), interval=\(settings.intervalMinutes)min")
                Task { @MainActor in
                    self.hrLogSettings = settings
                }
                hrLogSettingsContinuation?.resume(returning: settings)
                hrLogSettingsContinuation = nil
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
                
                // Auto-connect if this is our saved ring
                if let (savedId, _) = loadRingFromFile(), savedId == peripheral.identifier.uuidString {
                    logger.info("Found saved ring, auto-connecting...")
                    Task {
                        try? await connect(to: ring)
                    }
                }
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
            self.stopBackgroundSync()
            
            if let error = error {
                logger.error("Disconnected with error: \(error.localizedDescription)")
            } else {
                logger.info("Disconnected")
            }
            
            // Auto-reconnect after unexpected disconnect
            logger.info("Will attempt reconnect in 5 seconds...")
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.tryAutoReconnect()
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
