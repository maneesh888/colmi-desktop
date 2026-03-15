// ColmiBLE - CoreBluetooth wrapper for Colmi smart rings
// Works on macOS and iOS

import Foundation
import CoreBluetooth
import ColmiProtocol

// MARK: - Ring Connection State

/// Connection state for a Colmi ring
public enum RingConnectionState: Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case syncing
}

// MARK: - Ring Info

/// Information about a discovered ring
public struct RingInfo: Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    
    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

// MARK: - ColmiRing

/// Main interface for interacting with a Colmi smart ring
@MainActor
public final class ColmiRing: NSObject, ObservableObject {
    
    // MARK: Published State
    
    @Published public private(set) var connectionState: RingConnectionState = .disconnected
    @Published public private(set) var connectedRing: RingInfo?
    @Published public private(set) var battery: BatteryInfo?
    @Published public private(set) var lastHeartRate: Int?
    @Published public private(set) var lastSpO2: Int?
    
    // MARK: Private
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?
    
    // Continuations for async operations
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var responseContinuation: CheckedContinuation<Data, Error>?
    
    // MARK: Init
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: Public API
    
    /// Scan for nearby rings
    public func scan(timeout: TimeInterval = 10) async throws -> [RingInfo] {
        // TODO: Implement scanning
        return []
    }
    
    /// Connect to a specific ring
    public func connect(to ring: RingInfo) async throws {
        // TODO: Implement connection
    }
    
    /// Connect to any available ring
    public func connect(timeout: TimeInterval = 30) async throws {
        // TODO: Implement auto-connect
    }
    
    /// Disconnect from current ring
    public func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectionState = .disconnected
        connectedRing = nil
    }
    
    /// Get battery level
    public func getBattery() async throws -> BatteryInfo {
        let response = try await sendPacket(BatteryInfo.requestPacket)
        guard let battery = BatteryInfo.parse(response) else {
            throw ColmiError.invalidResponse
        }
        self.battery = battery
        return battery
    }
    
    /// Enable HR monitoring
    public func enableHRMonitoring(intervalMinutes: Int = 5) async throws {
        let settings = HRLogSettings(enabled: true, intervalMinutes: intervalMinutes)
        _ = try await sendPacket(settings.writePacket())
    }
    
    /// Enable stress monitoring
    public func enableStressMonitoring() async throws {
        _ = try await sendPacket(StressSettings.enablePacket())
    }
    
    /// Enable HRV monitoring
    public func enableHRVMonitoring() async throws {
        _ = try await sendPacket(HRVSettings.enablePacket())
    }
    
    /// Get HR log for a specific date
    public func getHeartRateLog(for date: Date) async throws -> HeartRateLog? {
        // TODO: Implement multi-packet parsing
        return nil
    }
    
    /// Get activity for a day
    public func getActivity(daysAgo: Int = 0) async throws -> DailyActivity? {
        // TODO: Implement multi-packet parsing
        return nil
    }
    
    /// Get sleep data
    public func getSleep() async throws -> [SleepSession] {
        // TODO: Implement sleep parsing
        return []
    }
    
    // MARK: Private
    
    private func sendPacket(_ packet: Data) async throws -> Data {
        guard let rx = rxCharacteristic else {
            throw ColmiError.notConnected
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.responseContinuation = continuation
            peripheral?.writeValue(packet, for: rx, type: .withoutResponse)
            
            // Timeout after 5 seconds
            Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                if self.responseContinuation != nil {
                    self.responseContinuation?.resume(throwing: ColmiError.timeout)
                    self.responseContinuation = nil
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ColmiRing: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Handle state changes
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Handle discovered devices
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectionState = .connected
            peripheral.discoverServices([CBUUID(string: ColmiUUID.service)])
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectionState = .disconnected
            self.connectionContinuation?.resume(throwing: error ?? ColmiError.connectionFailed)
            self.connectionContinuation = nil
        }
    }
    
    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectionState = .disconnected
            self.connectedRing = nil
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ColmiRing: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        Task { @MainActor in
            for char in characteristics {
                if char.uuid == CBUUID(string: ColmiUUID.rxCharacteristic) {
                    self.rxCharacteristic = char
                } else if char.uuid == CBUUID(string: ColmiUUID.txCharacteristic) {
                    self.txCharacteristic = char
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            
            if self.rxCharacteristic != nil && self.txCharacteristic != nil {
                self.connectionContinuation?.resume()
                self.connectionContinuation = nil
            }
        }
    }
    
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        Task { @MainActor in
            self.responseContinuation?.resume(returning: data)
            self.responseContinuation = nil
        }
    }
}

// MARK: - Errors

public enum ColmiError: Error, LocalizedError {
    case bluetoothUnavailable
    case notConnected
    case connectionFailed
    case timeout
    case invalidResponse
    case ringNotFound
    
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable: return "Bluetooth is not available"
        case .notConnected: return "Not connected to ring"
        case .connectionFailed: return "Failed to connect to ring"
        case .timeout: return "Operation timed out"
        case .invalidResponse: return "Invalid response from ring"
        case .ringNotFound: return "Ring not found"
        }
    }
}
