# Colmi Ring BLE Protocol

This document describes the Bluetooth Low Energy (BLE) protocol used by Colmi smart rings (R02, R06, R09, R10 and compatible).

## Overview

The ring uses a Nordic UART Service (NUS) variant for communication:
- No pairing or security keys required
- 16-byte packet structure
- Simple checksum for validation

## BLE UUIDs

| Name | UUID |
|------|------|
| **UART Service** | `6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E` |
| **RX Characteristic** (write) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| **TX Characteristic** (notify) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

Additional standard services:
| Name | UUID |
|------|------|
| Device Info Service | `0000180A-0000-1000-8000-00805F9B34FB` |
| Hardware Revision | `00002A27-0000-1000-8000-00805F9B34FB` |
| Firmware Revision | `00002A26-0000-1000-8000-00805F9B34FB` |

## Packet Structure

All packets are exactly 16 bytes:

```
Byte 0:      Command ID
Bytes 1-14:  Payload (command-specific)
Byte 15:     Checksum
```

### Checksum

The checksum is calculated as: `sum(bytes[0..14]) & 0xFF`

```swift
func checksum(_ data: Data) -> UInt8 {
    let sum = data.prefix(15).reduce(0) { $0 + UInt16($1) }
    return UInt8(sum & 0xFF)
}
```

### Error Bit

Response packets may have bit 7 of the command byte set to indicate an error:
- `0x03` = successful battery response
- `0x83` = battery command error

## Commands

### 0x03 - Battery Level

**Request:** `[0x03, 0x00...0x00, checksum]`

**Response:**
```
Byte 0:  0x03 (command)
Byte 1:  Battery level (0-100)
Byte 2:  Charging status (0=no, 1=yes)
Byte 15: Checksum
```

### 0x01 - Set Time

**Request:**
```
Byte 0:  0x01 (command)
Byte 1:  Year - 2000 (e.g., 24 for 2024)
Byte 2:  Month (1-12)
Byte 3:  Day (1-31)
Byte 4:  Hour (0-23)
Byte 5:  Minute (0-59)
Byte 6:  Second (0-59)
Byte 7:  Week day (0=auto)
Byte 15: Checksum
```

### 0x15 (21) - Read Heart Rate Log

Requests heart rate data for a specific day. Returns multiple packets.

**Request:**
```
Byte 0:    0x15 (command)
Bytes 1-4: Unix timestamp (little-endian, start of day)
Byte 15:   Checksum
```

**Response (multi-packet):**

Packet 0 (header):
```
Byte 0: 0x15
Byte 1: 0x00 (sub-type)
Byte 2: Number of data packets to follow
Byte 3: Interval in minutes (usually 5)
```

Packet 1 (first data):
```
Byte 0:    0x15
Byte 1:    0x01 (sub-type)
Bytes 2-5: Timestamp (little-endian)
Bytes 6-14: First 9 HR values
```

Packets 2+:
```
Byte 0:    0x15
Byte 1:    N (sub-type, 2..N)
Bytes 2-14: 13 HR values each
```

### 0x69 (105) - Start Real-Time Reading

Starts a real-time measurement (heart rate or SpO2).

**Request:**
```
Byte 0: 0x69 (command)
Byte 1: Reading type (0x01=HR, 0x03=SpO2)
Byte 2: 0x01 (start action)
```

**Response (continuous):**
```
Byte 0: 0x69
Byte 1: Reading type (0x01=HR, 0x03=SpO2)
Byte 2: Error code (0x00=success)
Byte 3: Value (BPM or SpO2%)
```

**Important notes:**
- Responses are sent continuously while measurement is active
- Initial responses may have value=0 while the sensor warms up
- **Wait up to 30 seconds** for a valid (non-zero) reading
- Ring should be snug on finger for accurate readings
- Always send stop command when done to save battery

### 0x6A (106) - Stop Real-Time Reading

**Request:**
```
Byte 0: 0x6A (command)
Byte 1: Reading type (0x01=HR, 0x03=SpO2)
Byte 2: 0x00 (stop action)
```

### Real-Time Reading Type Values

| Type | Value | Description |
|------|-------|-------------|
| Heart Rate | 0x01 | BPM (30-200 typical) |
| SpO2 | 0x03 | Percentage (90-100 typical) |

### 0x50 (80) - Find Device

Makes the ring vibrate.

**Request:** `[0x50, 0x00...0x00, checksum]`

### 0x43 (67) - Read Steps/Activity

Requests activity data for a specific day (relative to today).

**Request:**
```
Byte 0:  0x43 (command)
Byte 1:  Day offset (0=today, 1=yesterday, etc.)
Byte 2:  0x0F (constant)
Byte 3:  0x00 
Byte 4:  0x5F
Byte 5:  0x01 (constant)
Byte 15: Checksum
```

**Response (multi-packet):**

Packet 0 (header):
```
Byte 0: 0x43
Byte 1: 0xF0 (header marker)
Byte 2: Total packet count
Byte 3: Calorie protocol (0=old, 1=new multiplied by 10)
```

Data packets (BCD-encoded dates):
```
Byte 0:    0x43
Byte 1:    Year (BCD, e.g., 0x24 = 2024)
Byte 2:    Month (BCD)
Byte 3:    Day (BCD)
Byte 4:    Time index (0-95 for 15-min intervals)
Byte 5:    Current packet index
Byte 6:    Total data packets
Bytes 7-8: Calories (little-endian, multiply by 10 if new protocol)
Bytes 9-10: Steps (little-endian)
Bytes 11-12: Distance in meters (little-endian)
```

### 0x2C (44) - Read SpO2 Log

Same multi-packet structure as heart rate log (0x15).

### 0x16 (22) - HR Log Settings (Continuous Monitoring)

Controls automatic heart rate recording.

**Read Request:**
```
Byte 0: 0x16
Byte 1: 0x01 (read mode)
```

**Write Request:**
```
Byte 0:  0x16
Byte 1:  0x02 (write mode)
Byte 2:  Enabled (0x01=on, 0x02=off)
Byte 3:  Interval in minutes (5, 10, 15, 30, 60 typical)
Byte 15: Checksum
```

**Response:**
```
Byte 0: 0x16
Byte 1: Unknown (usually 0x01)
Byte 2: Enabled (0x01=on, 0x02=off)
Byte 3: Interval in minutes
```

### Other Commands

| Command | Name | Notes |
|---------|------|-------|
| 0x08 | Power Off | Turns off the ring |
| 0x37 | Read Stress | Stress measurement data (format undocumented) |

## Data Formats

### Heart Rate Log

The daily heart rate log contains 288 readings (one every 5 minutes for 24 hours).

- Value 0 = no data for that time slot
- Values 30-250 = valid BPM readings

### Ring Names

Compatible rings typically advertise as:
- `R02_XXXX`
- `R06_XXXX`
- `R09_XXXX`
- `R10_XXXX`

Where XXXX is the last 4 characters of the MAC address.

## References

- [tahnok/colmi_r02_client](https://github.com/tahnok/colmi_r02_client) - Python client
- [Gadgetbridge PR #3896](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/3896) - Android support
- [atc1441/ATC_RF03_Ring](https://github.com/atc1441/ATC_RF03_Ring) - Custom firmware
- [tahnok's notes](https://notes.tahnok.ca/) - Reverse engineering notes
