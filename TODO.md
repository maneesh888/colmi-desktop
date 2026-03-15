# Colmi R09 Feature TODO

## ✅ Done
- [x] HR real-time measurement (0x69)
- [x] SpO2 real-time measurement (0x6A)
- [x] Battery level (0x03)
- [x] HR log sync (0x15)
- [x] HR monitoring settings (0x16)
- [x] SpO2 log sync (0x2C)
- [x] Steps/Activity sync (0x43)
- [x] Stress monitoring settings (0x36)
- [x] Stress log sync (0x37)
- [x] HRV monitoring settings (0x38)
- [x] HRV log sync (0x39)
- [x] CLI with --history and --enable-monitoring

## 🔨 To Build (Priority Order)

### 1. Sleep Tracking (0xbc + 0x27)
- Big Data V2 command
- Sleep stages: Light/Deep/REM/Awake
- Sleep start/end times
- **Status:** Protocol documented, ready to implement

### 2. SpO2 Monitoring Settings (0x2c)
- Enable/disable continuous SpO2 monitoring
- Similar to HR settings (0x16)
- **Status:** Simple, just need to add

### 3. Goals (0x21)
- Set step/calorie/distance/sport/sleep goals
- Read current goals
- **Status:** Protocol documented

### 4. Notifications (0x73)
- Push notifications to ring (calls, messages)
- May require pairing/bonding
- **Status:** Needs testing

### 5. Set Time (0x01)
- Sync time with ring on connect
- Already have packet format
- **Status:** Easy to add

### 6. Phone Name (0x04)
- Set phone/app identity on ring
- **Status:** Low priority

### 7. Factory Reset (0xff)
- Reset ring to defaults
- **Status:** Dangerous, add with confirmation

## 🧪 Testing Checklist

Before adding new features, verify current ones work:

- [ ] Real-time HR reads correctly when ring on finger
- [ ] Real-time SpO2 reads correctly
- [ ] --enable-monitoring actually enables logging on ring
- [ ] --history syncs HR logs after monitoring enabled
- [ ] --history syncs activity/steps
- [ ] Stress readings appear after stress monitoring enabled
- [ ] HRV readings appear after HRV monitoring enabled

## 📝 Notes

- Ring model: Colmi R09
- Reference: Gadgetbridge ColmiR0x implementation
- Python reference: tahnok/colmi_r02_client
- Data stored in: ~/clawd/health/
