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
    
    @Test("Activity parser with multi-packet response")
    func testActivityParserMultiPacket() {
        let parser = ActivityParser()
        
        // Simulate R09 response from real device capture:
        // Header: 43 F0 02 01 = 2 packets, new calorie protocol
        var header = Data(count: 16)
        header[0] = 0x43  // readActivity command
        header[1] = 0xF0  // Header marker
        header[2] = 0x02  // 2 data packets to follow
        header[3] = 0x01  // New calorie protocol
        header[15] = ColmiPacket.checksum(header)
        
        // First parse: header, should return nil
        var result = parser.parse(header)
        #expect(result == nil)
        
        // Data packet 1: 43 26 03 10 28 00 01 d5 00 4c 00 2f 00 ...
        // year=26 (BCD=26=2026), month=03, day=16 (BCD=10=16), timeIndex=40 (0x28=10:00)
        // packetIndex=0, totalPackets=1, calories=213*10=2130, steps=76, distance=47
        var data1 = Data(count: 16)
        data1[0] = 0x43
        data1[1] = 0x26  // BCD year (26 = 2026)
        data1[2] = 0x03  // BCD month (03 = March)
        data1[3] = 0x16  // BCD day (16 = 16th)
        data1[4] = 0x28  // timeIndex = 40 (10:00 AM)
        data1[5] = 0x00  // packetIndex
        data1[6] = 0x02  // totalPackets (2)
        data1[7] = 0xD5  // calories low
        data1[8] = 0x00  // calories high (213 * 10 = 2130 with new protocol)
        data1[9] = 0x4C  // steps low (76)
        data1[10] = 0x00 // steps high
        data1[11] = 0x2F // distance low (47m)
        data1[12] = 0x00 // distance high
        data1[15] = ColmiPacket.checksum(data1)
        
        // Second parse: data packet 1, should return nil
        result = parser.parse(data1)
        #expect(result == nil)
        
        // Data packet 2 (last): same format but packetIndex=1
        var data2 = Data(count: 16)
        data2[0] = 0x43
        data2[1] = 0x26
        data2[2] = 0x03
        data2[3] = 0x16
        data2[4] = 0x2C  // timeIndex = 44 (11:00 AM)
        data2[5] = 0x01  // packetIndex = 1 (last)
        data2[6] = 0x02  // totalPackets = 2
        data2[7] = 0x64  // calories = 100 * 10 = 1000
        data2[8] = 0x00
        data2[9] = 0x32  // steps = 50
        data2[10] = 0x00
        data2[11] = 0x19 // distance = 25m
        data2[12] = 0x00
        data2[15] = ColmiPacket.checksum(data2)
        
        // Third parse: last data packet, should return DailyActivity
        result = parser.parse(data2)
        #expect(result != nil)
        #expect(result?.details.count == 2)
        #expect(result?.totalSteps == 126)  // 76 + 50
        #expect(result?.totalCalories == 3130)  // 2130 + 1000
        #expect(result?.totalDistance == 72)  // 47 + 25
    }
    
    @Test("Activity parser no data response")
    func testActivityParserNoData() {
        let parser = ActivityParser()
        
        // No data response: 43 FF ...
        var noData = Data(count: 16)
        noData[0] = 0x43
        noData[1] = 0xFF
        noData[15] = ColmiPacket.checksum(noData)
        
        let result = parser.parse(noData)
        #expect(result == nil)
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
