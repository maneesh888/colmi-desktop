# ColmiSync Priority List

## Current Status (2026-04-03)

### Working ✅
- Real-time HR, SpO2, Battery
- Step history sync (0x43)
- Enable monitoring settings (HR, Stress, HRV)
- SQLite storage
- JSON export for AI analysis

### Not Working on RTL8762 chip ❌
- HR history (0x15) → returns 0xFF
- Sleep history (0xBC 0x27) → returns 0 bytes
- SpO2 history (0x2C) → no data
- Stress history (0x37) → returns 0xFF
- HRV history (0x39) → returns 0xFF

### Known Issue
- R03/R09 with **RTL8762E chip** has protocol differences
- R02/R03 with **BlueX RF03 chip** works fully
- Gadgetbridge has same bug: https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/4393

---

## Priority 1: Get History Working on RTL8762

### Option A: Capture QRing Protocol
- [ ] Capture BLE traffic when QRing syncs sleep/HR history
- [ ] Decode what commands QRing sends differently
- [ ] Implement in ColmiSync

### Option B: Wait for Gadgetbridge Fix
- Monitor issue #4393 for updates

---

## Priority 2: Fix Timestamp Parsing ✅
- [x] Activity timestamps show year 2000 instead of 2026
- [x] BCD year parsing issue in ActivityParser
- Fixed: RTL8762 sends 0x00 for year, now fallback to current year

---

## Priority 3: AI Health Analyzer Integration
- [ ] Collect enough data (wear ring overnight)
- [x] Design AI prompt for health analysis → docs/AI_HEALTH_PROMPT.md
- [x] Build daily/weekly summary reports → HealthSummary with trends

---

## Priority 4: Polish
- [ ] Daemon auto-sync reliability
- [ ] Better error handling for disconnects
- [ ] macOS menu bar app (future)

---

## Hardware Notes

| Ring | Chip | History Sync |
|------|------|--------------|
| R02 | BlueX RF03 | ✅ Works |
| R03 (old) | BlueX RF03 | ✅ Works |
| R03 (new) | RTL8762E | ❌ Partial |
| R09 | RTL8762E | ❌ Partial |

Maneesh's R03 = RTL8762E (partial support)
