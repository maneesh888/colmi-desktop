import Foundation

/// Command IDs for Colmi ring protocol
public enum ColmiCommand: UInt8, CaseIterable, Sendable {
    // System
    case setTime = 0x01             // Set ring time
    case battery = 0x03             // Get battery level
    case phoneName = 0x04           // Set phone/app name
    case powerOff = 0x08            // Power off ring
    case preferences = 0x0A         // General preferences
    
    // Heart Rate
    case readHeartRate = 0x15       // Daily heart rate logs
    case hrLogSettings = 0x16       // HR log settings (continuous monitoring)
    
    // Goals
    case goals = 0x21               // Step/calorie/distance goals
    
    // SpO2
    case spo2Settings = 0x2C        // SpO2 monitoring settings
    
    // Stress & HRV
    case stressSettings = 0x36      // Stress monitoring settings
    case readStress = 0x37          // Stress data (30 min intervals)
    case hrvSettings = 0x38         // HRV monitoring settings
    case readHRV = 0x39             // HRV data
    
    // Activity
    case readActivity = 0x43        // Steps/calories/distance
    
    // Device
    case findDevice = 0x50          // Make ring vibrate (if supported)
    
    // Real-time measurements
    case realTimeHR = 0x69          // Real-time heart rate
    case realTimeSpO2 = 0x6A        // Real-time SpO2
    
    // Notifications
    case notification = 0x73        // Push notification to ring
    
    // Big Data (V2)
    case bigDataV2 = 0xBC           // Sleep, SpO2 history
    
    // Factory reset
    case factoryReset = 0xFF        // Reset to defaults
    
    /// Human-readable name
    public var name: String {
        switch self {
        case .setTime: return "Set Time"
        case .battery: return "Battery"
        case .phoneName: return "Phone Name"
        case .powerOff: return "Power Off"
        case .preferences: return "Preferences"
        case .readHeartRate: return "HR Log"
        case .hrLogSettings: return "HR Settings"
        case .goals: return "Goals"
        case .spo2Settings: return "SpO2 Settings"
        case .stressSettings: return "Stress Settings"
        case .readStress: return "Stress Log"
        case .hrvSettings: return "HRV Settings"
        case .readHRV: return "HRV Log"
        case .readActivity: return "Activity"
        case .findDevice: return "Find Device"
        case .realTimeHR: return "Real-time HR"
        case .realTimeSpO2: return "Real-time SpO2"
        case .notification: return "Notification"
        case .bigDataV2: return "Big Data"
        case .factoryReset: return "Factory Reset"
        }
    }
}

/// Big Data subtypes for command 0xBC
public enum BigDataType: UInt8, Sendable {
    case sleep = 0x27
    case spo2 = 0x2A
}

/// Sleep stage types
public enum SleepStage: UInt8, Codable, Sendable {
    case light = 0x02
    case deep = 0x03
    case rem = 0x04
    case awake = 0x05
    
    public var name: String {
        switch self {
        case .light: return "Light"
        case .deep: return "Deep"
        case .rem: return "REM"
        case .awake: return "Awake"
        }
    }
}
