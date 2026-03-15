# ColmiKit

A cross-platform Swift package for communicating with Colmi smart rings (R02, R06, R09, R10).

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   Apps                          │
├──────────────┬──────────────┬──────────────────┤
│  macOS CLI   │  macOS Menu  │   iOS App        │
│  (daemon)    │    Bar App   │   (future)       │
└──────┬───────┴──────┬───────┴────────┬─────────┘
       │              │                │
       ▼              ▼                ▼
┌─────────────────────────────────────────────────┐
│              ColmiKit (Package)                 │
├─────────────────────────────────────────────────┤
│  ColmiProtocol   │  Pure Swift, no dependencies │
│  - Packet build  │  - Works everywhere          │
│  - Packet parse  │  - Unit testable             │
│  - Data models   │                              │
├──────────────────┼──────────────────────────────┤
│  ColmiBLE        │  CoreBluetooth wrapper       │
│  - Scan/Connect  │  - macOS + iOS compatible    │
│  - Read/Write    │  - async/await API           │
│  - Auto-reconnect│                              │
└─────────────────────────────────────────────────┘
```

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../ColmiKit")  // Local
    // or
    .package(url: "https://github.com/user/colmi-desktop", from: "1.0.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "ColmiKit", package: "ColmiKit"),
        // or just the protocol layer:
        .product(name: "ColmiProtocol", package: "ColmiKit"),
    ]
)
```

## Usage

### Protocol Layer (No BLE)

```swift
import ColmiProtocol

// Create a battery request packet
let packet = BatteryInfo.requestPacket

// Parse a response
if let battery = BatteryInfo.parse(responseData) {
    print("Battery: \(battery.level)%")
}

// Create HR log request for today
let hrRequest = HeartRateLogParser.requestPacket(for: Date())

// Parse multi-packet HR log response
let parser = HeartRateLogParser()
for packet in receivedPackets {
    if let log = parser.parse(packet) {
        print("HR readings: \(log.validReadings.count)")
        print("Average: \(log.average ?? 0) bpm")
    }
}
```

### Full Kit with BLE

```swift
import ColmiKit

let ring = ColmiRing()

// Scan and connect
try await ring.connect()

// Read battery
let battery = try await ring.getBattery()
print("Battery: \(battery.level)%")

// Enable continuous monitoring
try await ring.enableHRMonitoring(intervalMinutes: 5)
try await ring.enableStressMonitoring()
try await ring.enableHRVMonitoring()

// Sync historical data
let hrLog = try await ring.getHeartRateLog(for: Date())
let activity = try await ring.getActivity(daysAgo: 0)
let sleep = try await ring.getSleep()
```

## Supported Features

| Feature | Command | Status |
|---------|---------|--------|
| Battery | 0x03 | ✅ |
| Real-time HR | 0x69 | ✅ |
| Real-time SpO2 | 0x6A | ✅ |
| HR Logs | 0x15 | ✅ |
| HR Settings | 0x16 | ✅ |
| SpO2 Logs | 0x2C | ✅ |
| Activity/Steps | 0x43 | ✅ |
| Stress Settings | 0x36 | ✅ |
| Stress Logs | 0x37 | ✅ |
| HRV Settings | 0x38 | ✅ |
| HRV Logs | 0x39 | ✅ |
| Sleep | 0xBC+0x27 | ✅ |
| Set Time | 0x01 | ✅ |
| Goals | 0x21 | 🔨 |
| Notifications | 0x73 | 🔨 |

## Supported Rings

- Colmi R02
- Colmi R06
- Colmi R09 ✅ (tested)
- Colmi R10

## Protocol Reference

See [PROTOCOL.md](../docs/PROTOCOL.md) for detailed BLE protocol documentation.

## Credits

- [tahnok/colmi_r02_client](https://github.com/tahnok/colmi_r02_client) - Python reference
- [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) - Android implementation
- [atc1441/ATC_RF03_Ring](https://github.com/atc1441/ATC_RF03_Ring) - Hardware research

## License

MIT
