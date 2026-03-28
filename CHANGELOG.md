# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-03-29

### Added
- **Core Features**
  - Ring discovery and connection via Bluetooth
  - Real-time heart rate monitoring
  - SpO2 (blood oxygen) monitoring
  - Activity tracking (steps, calories, distance)
  - Battery level monitoring
  - Find ring (vibrate)
  - Auto-reconnect

- **Data Sync**
  - Historical HR logs (288 readings/day) — R02/R06
  - Historical SpO2 logs — R02/R06
  - Steps/activity history (all models)
  - Continuous HR monitoring settings
  - 7-day history sync on connect
  - Sleep inference engine for R09

- **Storage**
  - JSON storage for AI consumption
  - SQLite storage (colmi_r02_client compatible schema)
  - Data saved to `~/clawd/health/`

- **CLI Mode**
  - `--cli` flag for headless operation
  - `--summary` mode for health data summary
  - `--scan-time` and `--retries` options
  - Exit codes for scripting

- **Background Sync**
  - launchd integration for hourly automatic sync
  - Install script: `scripts/install-launchd.sh`
  - Uninstall script: `scripts/uninstall-launchd.sh`

- **Architecture**
  - ColmiKit Swift Package (reusable on macOS + iOS)
  - ColmiProtocol: Pure Swift packet encoding/decoding
  - ColmiBLE: CoreBluetooth wrapper with async/await API
  - Xcode project with proper entitlements

### Known Limitations
- Sleep tracking: Protocol unknown, needs reverse engineering
- R09 historical HR/SpO2: Returns empty (may use different protocol)
- Stress/HRV data: Protocol unknown

### Supported Rings
- Colmi R02 ✅
- Colmi R06 ✅
- Colmi R09 ✅ (with noted limitations)
- Colmi R10 (untested, should work)
- Any ring using the QRing app protocol

---

*Your health data, on your device, under your control.*
