# Colmi Desktop

**Privacy-first health ring data sync for macOS**

> Your health data, on your device, under your control.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## What is this?

A native macOS menu bar app that syncs data from Colmi smart rings directly to your Mac. No cloud, no account, no subscription — just your data on your device.

## Features

- 🔒 **100% Local** — Data never leaves your machine
- ❤️ **Heart Rate** — Real-time and historical readings
- 🫁 **SpO2** — Blood oxygen monitoring
- 🚶 **Activity** — Steps, calories, distance
- 😴 **Sleep** — Sleep tracking data *(coming soon)*
- ⚡ **Menu Bar App** — Always accessible, never in the way
- 🔄 **Auto-Connect** — Remembers your ring, reconnects automatically

## Supported Rings

Any Colmi ring that uses the **QRing app** should work:

| Ring | Status |
|------|--------|
| Colmi R02 | ✅ Supported |
| Colmi R06 | ✅ Supported |
| Colmi R09 | ✅ Tested |
| Colmi R10 | ✅ Supported |

## Installation

### Requirements
- macOS 13.0 (Ventura) or later
- A Colmi smart ring

### Build from Source

```bash
git clone https://github.com/YOUR_USERNAME/colmi-desktop.git
cd colmi-desktop/macos/ColmiSync
swift build
swift run
```

### Xcode

Open `macos/ColmiSync/Package.swift` in Xcode and run.

## Usage

1. **Launch** the app — it appears in your menu bar
2. **Scan** for your ring (make sure it's not connected to your phone)
3. **Connect** — tap your ring in the list
4. **Sync** — click "Sync Now" to read your health data

Data is stored locally in `~/.colmisync/` and `~/clawd/health/`.

## How It Works

The app communicates with your ring over Bluetooth Low Energy (BLE) using a reverse-engineered protocol. Your ring broadcasts health data which we read and store locally.

### Protocol

Based on the excellent reverse engineering work by:
- [tahnok/colmi_r02_client](https://github.com/tahnok/colmi_r02_client) (Python)
- [Gadgetbridge PR #3896](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/3896) (Android)
- [atc1441/ATC_RF03_Ring](https://github.com/atc1441/ATC_RF03_Ring) (Custom Firmware)

### BLE UUIDs

```
Service:     6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E
RX (Write):  6E400002-B5A3-F393-E0A9-E50E24DCCA9E
TX (Notify): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
```

See [docs/PROTOCOL.md](docs/PROTOCOL.md) for detailed protocol documentation.

## Roadmap

- [x] Ring discovery & pairing
- [x] Real-time heart rate
- [x] SpO2 reading
- [x] Steps & activity sync
- [x] Auto-reconnect
- [ ] Sleep data sync
- [ ] Historical data charts
- [ ] Background sync daemon
- [ ] Proper app bundle (DMG release)
- [ ] Linux support

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting PRs.

### Development

```bash
cd macos/ColmiSync
swift build
swift test
```

## Why?

Colmi rings are affordable ($20-35) and capable health trackers, but the official app requires cloud accounts and sends your health data to servers in China. This project lets you use the hardware without the privacy tradeoffs.

## Community

- [Gadgetbridge Discord](https://discord.gg/K4wvDqDZvn) — Colmi reverse engineering discussion
- [tahnok's notes](https://notes.tahnok.ca/) — Protocol documentation

## License

MIT — see [LICENSE](LICENSE)

---

**Disclaimer:** This is an unofficial project. Not affiliated with Colmi. Use at your own risk.
