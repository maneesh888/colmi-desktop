# Colmi Desktop

**Take back control of your health data.**

> Why send your heart rate, sleep patterns, and activity data to servers in China when you can keep it local and feed it to your own AI?

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## The Problem

Affordable smart rings like Colmi ($20-35) pack impressive health sensors — heart rate, SpO2, sleep tracking, activity monitoring. But here's the catch: the official app requires cloud accounts and sends your most personal biometric data to third-party servers.

**Your health data is too valuable to give away.**

## The Solution

Colmi Desktop is a native macOS menu bar app that:

1. **Syncs directly** with your Colmi ring over Bluetooth
2. **Stores everything locally** on your Mac
3. **Feeds data to your own AI** (like [Clawdbot](https://github.com/clawdbot/clawdbot)) for personalized health insights

No accounts. No cloud. No subscription. Just your data, under your control.

## Features

| Feature | Status |
|---------|--------|
| ❤️ Real-time Heart Rate | ✅ |
| 🫁 SpO2 (Blood Oxygen) | ✅ |
| 🚶 Steps & Calories | ✅ |
| 🔋 Battery Level | ✅ |
| 📳 Find Ring (Vibrate) | ✅ |
| 🔄 Auto-Reconnect | ✅ |
| 😴 Sleep Tracking | 🚧 Coming Soon |
| 📊 Historical Data | 🚧 Coming Soon |
| 🤖 Clawdbot Integration | 🚧 Coming Soon |

## Supported Rings

Any Colmi ring using the **QRing app** protocol:

- ✅ Colmi R09
- ✅ Colmi R06  
- ✅ Colmi R09 *(actively tested)*
- ✅ Colmi R10

## Quick Start

### Requirements
- macOS 13.0 (Ventura) or later
- A Colmi smart ring
- Xcode 15+ or Swift 5.9+

### Build & Run

```bash
git clone https://github.com/YOUR_USERNAME/colmi-desktop.git
cd colmi-desktop/macos/ColmiSync
swift build
swift run
```

The app appears in your menu bar. Click to scan, connect your ring, and start syncing.

### CLI Mode

For scripted/cron usage, run in CLI mode:

```bash
# Basic sync (reads battery, HR, SpO2)
swift run ColmiSync --cli

# With options
swift run ColmiSync --cli --scan-time 60 --retries 5
```

**Options:**
- `--scan-time <seconds>` - Time to scan for ring (default: 30)
- `--retries <count>` - Connection retry attempts (default: 3)

**Notes:**
- HR and SpO2 measurements take up to 30 seconds each (sensor warm-up)
- Results are saved to `~/clawd/health/latest.json`
- Ring must be paired first via the menu bar app

### Background Sync (launchd)

For automatic hourly syncs, install the background service:

```bash
# Build and install
./scripts/install-launchd.sh

# Commands
launchctl start com.colmisync.sync   # Run now
launchctl stop com.colmisync.sync    # Stop
tail -f ~/.colmisync/sync.log        # View logs

# Uninstall
./scripts/uninstall-launchd.sh
```

### Data Storage

Health data is stored locally:
- `~/.colmisync/` — App config & paired device
- `~/clawd/health/` — Health data JSON files (ready for AI consumption)

## Architecture

### System Overview

```
┌─────────────────┐     BLE      ┌─────────────────┐
│   Colmi Ring    │◄────────────►│  Colmi Desktop  │
└─────────────────┘              └────────┬────────┘
                                          │
                                          ▼
                                 ┌─────────────────┐
                                 │  Local Storage  │
                                 │  ~/clawd/health │
                                 └────────┬────────┘
                                          │
                                          ▼
                                 ┌─────────────────┐
                                 │    Clawdbot     │
                                 │   (Your AI)     │
                                 └─────────────────┘
```

### Package Structure (ColmiKit)

The core logic is packaged as a reusable Swift Package that works on **macOS and iOS**:

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

See [ColmiKit/README.md](ColmiKit/README.md) for package documentation.

## The Vision

This project is part of a larger mission: **democratizing personal AI**.

Instead of:
- Sending health data to corporate clouds
- Paying subscriptions for "insights"
- Having no control over your own biometrics

We enable:
- Local-first data ownership
- AI analysis on YOUR terms
- Open protocols anyone can build on

Your health data should train YOUR AI, not someone else's.

## Technical Details

### BLE Protocol

Built on reverse-engineered protocol documentation from the community:

- [tahnok/colmi_r02_client](https://github.com/tahnok/colmi_r02_client) — Python reference
- [Gadgetbridge PR #3896](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/3896) — Android support
- [atc1441/ATC_RF03_Ring](https://github.com/atc1441/ATC_RF03_Ring) — Custom firmware

### UUIDs

```
Service:     6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E
RX (Write):  6E400002-B5A3-F393-E0A9-E50E24DCCA9E
TX (Notify): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
```

See [docs/PROTOCOL.md](docs/PROTOCOL.md) for packet formats.

## Roadmap

### Core Features
- [x] Ring discovery & connection
- [x] Real-time heart rate
- [x] SpO2 monitoring  
- [x] Activity tracking (steps/calories)
- [x] Battery level
- [x] Find ring (vibrate)
- [x] Auto-reconnect

### Health Data
- [x] HR logs (historical 24h data, 288 readings/day)
- [x] SpO2 logs (historical data)
- [x] Continuous monitoring settings (enable/disable, interval)
- [x] 7-day history sync on connect
- [x] JSON storage for all data types
- [x] CLI mode for scripted sync
- [ ] Sleep tracking & analysis (infer from HR patterns)
- [ ] Stress data (protocol undocumented)
- [ ] HRV (may not be hardware supported)

### Clawdbot Integration
- [x] Local JSON format for AI consumption
- [ ] Health data skill for Clawdbot
- [ ] Daily health summaries
- [ ] Anomaly detection (unusual HR, poor sleep)
- [ ] Natural language queries ("How was my sleep?")
- [ ] Proactive health insights

### Polish
- [ ] Background sync daemon (launchd)
- [ ] Health trend charts
- [ ] Proper .app bundle & DMG releases
- [ ] macOS notifications
- [ ] Linux support (maybe)

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

This is an open source portfolio project — clean code, good documentation, and thoughtful PRs are appreciated.

## Community

- [Gadgetbridge Discord](https://discord.gg/K4wvDqDZvn) — Ring protocol discussion
- [Clawdbot Discord](https://discord.com/invite/clawd) — AI assistant community

## License

MIT — do whatever you want with it.

---

**Built by [Maneesh](https://github.com/YOUR_USERNAME)** — iOS developer, privacy advocate, believer in local-first AI.

*Your body generates the data. You should own it.*
