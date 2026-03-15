import Foundation

/// BLE UUIDs for Colmi rings (Nordic UART Service variant)
public enum ColmiUUID {
    // Primary UART Service (V1)
    public static let service = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let rxCharacteristic = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // Write to ring
    public static let txCharacteristic = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // Notifications from ring
    
    // V2 Service (newer firmware)
    public static let serviceV2 = "DE5BF728-D711-4E47-AF26-65E3012A5DC7"
    public static let commandV2 = "DE5BF72A-D711-4E47-AF26-65E3012A5DC7"
    public static let notifyV2 = "DE5BF729-D711-4E47-AF26-65E3012A5DC7"
    
    // Device Info Service
    public static let deviceInfoService = "0000180A-0000-1000-8000-00805F9B34FB"
    public static let hardwareRevision = "00002A27-0000-1000-8000-00805F9B34FB"
    public static let firmwareRevision = "00002A26-0000-1000-8000-00805F9B34FB"
}
