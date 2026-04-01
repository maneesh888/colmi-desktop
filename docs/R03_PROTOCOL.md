# R03 Protocol Research

## Summary
The Colmi R03 uses a **different chip** (REALTEK RTL8762E) compared to R02 (BlueX RF03).
The R03 **rejects** the standard R02 protocol commands for historical data.

## What Works on R03
| Command | Byte | Status |
|---------|------|--------|
| Battery | 0x03 | ✅ Works |
| Real-time HR | 0x69 | ✅ Works |
| Real-time SpO2 | 0x69 (subtype 0x03) | ✅ Works |
| Find Device | 0x50 | ✅ Works |
| Set Time | 0x01 | ✅ Works |

## What Fails on R03
| Command | Byte | Response |
|---------|------|----------|
| HR Log | 0x15 | 0xFF (error) |
| Steps | 0x43 | 0xFF (error) |
| Big Data | 0xBC | No response |
| Sleep (0x27) | 0x27 | 0xEE (unknown error) |
| 0x73 subtypes | 0x73 | 0xF3 0xEE (error) |

## R02 Protocol Reference (from colmi_r02_client)
- HR Log: `0x15 + timestamp (4 bytes LE)`
- Steps: `0x43 + day_offset + 0x0f 0x00 0x5f 0x01`
- These work on R02/R06 but NOT on R03

## Next Steps
1. **Sniff QRing app** with nRF Connect on Android
2. Capture BLE traffic when QRing syncs historical data
3. Compare packet structure to find R03-specific commands

## Hardware Info
- **Chip:** REALTEK RTL8762E
- **App:** QRing
- **BLE Service:** 6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E (same as R02)

## Test Results (2026-04-01)

### Day Offset Test
```
📤 15 00 00 00 00 00 00 00 00 00 00 00 00 00 00 15
📥 15 FF 00 00 00 00 00 00 00 00 00 00 00 00 00 14 ❌
```

### Timestamp Test
```
📤 15 C0 27 CC 69 00 00 00 00 00 00 00 00 00 00 31
📥 (timeout - no response)
```

### Other Commands
```
0x17 → 0x97 0xEE (error)
0x27 → 0xA7 0xEE (error)
0x73 → 0xF3 0xEE + streaming 0x73 packets (real-time activity)
```

## Observations
- 0x73 packets stream continuously (real-time activity data)
- Error code 0xEE appears instead of 0xFF for some commands
- The ring IS communicating, just using different command format

---
*Last updated: 2026-04-02*
