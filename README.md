# Colmi Desktop

**Privacy-first health ring data sync for macOS**

Your health data, on your device, under your control.

## What is this?

A native macOS menu bar app that syncs data from Colmi smart rings (R02, R06, R09, R10) directly to your Mac. No cloud required.

## Features

- 🔒 **100% Local** - Data never leaves your machine
- 📊 **Health Metrics** - Heart rate, SpO2, sleep, steps
- ⚡ **Menu Bar App** - Always accessible, never in the way
- 🔄 **Auto Sync** - Background sync when ring is nearby

## Supported Rings

Any Colmi ring that uses the **QRing app** should work:
- Colmi R02
- Colmi R06
- Colmi R09
- Colmi R10

## Building

```bash
cd macos/ColmiSync
swift build
swift run
```

Or open `macos/ColmiSync/Package.swift` in Xcode.

## Protocol

Based on the excellent reverse engineering work by:
- [tahnok/colmi_r02_client](https://github.com/tahnok/colmi_r02_client) (Python)
- [Gadgetbridge PR #3896](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/3896) (Android)
- [atc1441/ATC_RF03_Ring](https://github.com/atc1441/ATC_RF03_Ring) (Firmware)

### BLE UUIDs

```
Service:  6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E
RX (Write): 6E400002-B5A3-F393-E0A9-E50E24DCCA9E
TX (Notify): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
```

## License

MIT
