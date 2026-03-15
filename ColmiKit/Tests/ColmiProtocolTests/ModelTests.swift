import Testing
@testable import ColmiProtocol

@Suite("Model Tests")
struct ModelTests {
    
    // MARK: - Battery Tests
    
    @Test("Battery parsing")
    func testBatteryParsing() {
        var packet = Data(count: 16)
        packet[0] = ColmiCommand.battery.rawValue
        packet[1] = 85  // 85%
        packet[2] = 0   // Not charging
        packet[15] = ColmiPacket.checksum(packet)
        
        let battery = BatteryInfo.parse(packet)
        #expect(battery != nil)
        #expect(battery?.level == 85)
        #expect(battery?.isCharging == false)
    }
    
    @Test("Battery request packet")
    func testBatteryRequest() {
        let packet = BatteryInfo.requestPacket
        #expect(ColmiPacket.commandType(packet) == .battery)
        #expect(ColmiPacket.isValid(packet))
    }
    
    // MARK: - HR Log Tests
    
    @Test("HR log settings write packet")
    func testHRLogSettingsWrite() {
        let settings = HRLogSettings(enabled: true, intervalMinutes: 5)
        let packet = settings.writePacket()
        
        #expect(ColmiPacket.commandType(packet) == .hrLogSettings)
        #expect(packet[1] == 0x02)  // Write subtype
        #expect(packet[2] == 0x01)  // Enabled
        #expect(packet[3] == 5)     // 5 minutes
    }
    
    @Test("HR log valid readings filter")
    func testHRLogValidReadings() {
        let readings = [0, 72, 75, 0, 80, 250, 65, 0]
        let log = HeartRateLog(date: Date(), readings: readings)
        
        let valid = log.validReadings
        #expect(valid == [72, 75, 80, 65])
        #expect(log.average == 73)  // (72+75+80+65)/4
    }
    
    // MARK: - Sleep Tests
    
    @Test("Sleep stage names")
    func testSleepStageNames() {
        #expect(SleepStage.light.name == "Light")
        #expect(SleepStage.deep.name == "Deep")
        #expect(SleepStage.rem.name == "REM")
        #expect(SleepStage.awake.name == "Awake")
    }
    
    @Test("Sleep session duration")
    func testSleepSessionDuration() {
        let start = Date()
        let end = start.addingTimeInterval(8 * 60 * 60)  // 8 hours
        
        let session = SleepSession(startTime: start, endTime: end, stages: [])
        #expect(session.durationMinutes == 480)
        #expect(session.durationFormatted == "8h 0m")
    }
    
    // MARK: - Activity Tests
    
    @Test("Activity totals")
    func testActivityTotals() {
        let now = Date()
        let details = [
            SportDetail(timestamp: now, steps: 1000, calories: 50, distance: 800),
            SportDetail(timestamp: now, steps: 2000, calories: 100, distance: 1600),
        ]
        let activity = DailyActivity(date: now, details: details)
        
        #expect(activity.totalSteps == 3000)
        #expect(activity.totalCalories == 150)
        #expect(activity.totalDistance == 2400)
        #expect(activity.totalDistanceKm == 2.4)
    }
    
    // MARK: - Stress Tests
    
    @Test("Stress settings packets")
    func testStressSettingsPackets() {
        let enable = StressSettings.enablePacket()
        #expect(ColmiPacket.commandType(enable) == .stressSettings)
        #expect(enable[1] == 0x02)
        #expect(enable[2] == 0x01)
        
        let disable = StressSettings.disablePacket()
        #expect(disable[2] == 0x00)
    }
    
    // MARK: - HRV Tests
    
    @Test("HRV settings packets")
    func testHRVSettingsPackets() {
        let enable = HRVSettings.enablePacket()
        #expect(ColmiPacket.commandType(enable) == .hrvSettings)
        #expect(enable[1] == 0x02)
        #expect(enable[2] == 0x01)
    }
}
