import Testing
import Foundation
@testable import ColmiSync

@Suite("Colmi Protocol Tests")
struct ColmiProtocolTests {
    
    @Test("Packet checksum calculation")
    func testChecksum() {
        // Empty packet should have checksum 0
        var packet = Data(count: 16)
        packet[0] = 0x03  // Battery command
        let checksum = ColmiPacket.checksum(packet)
        #expect(checksum == 0x03)
        
        // Verify make_packet adds correct checksum
        let made = ColmiPacket.make(command: .battery)
        #expect(ColmiPacket.isValid(made))
        #expect(made[0] == 0x03)
        #expect(made[15] == 0x03)
    }
    
    @Test("Battery response parsing")
    func testBatteryParsing() {
        // Example from Python: bytearray(b'\x03@\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00C')
        // Battery: 64%, not charging
        var packet = Data(count: 16)
        packet[0] = 0x03  // Command
        packet[1] = 0x40  // 64% battery
        packet[2] = 0x00  // Not charging
        packet[15] = 0x43 // Checksum
        
        let battery = BatteryInfo.parse(packet)
        #expect(battery != nil)
        #expect(battery?.level == 64)
        #expect(battery?.isCharging == false)
    }
    
    @Test("Battery charging state")
    func testBatteryCharging() {
        var packet = Data(count: 16)
        packet[0] = 0x03
        packet[1] = 0x50  // 80%
        packet[2] = 0x01  // Charging
        packet[15] = ColmiPacket.checksum(packet)
        
        let battery = BatteryInfo.parse(packet)
        #expect(battery?.level == 80)
        #expect(battery?.isCharging == true)
    }
    
    @Test("Set time packet format")
    func testSetTimePacket() {
        let date = Date(timeIntervalSince1970: 1710288000) // 2024-03-13 00:00:00 UTC
        let packet = ColmiPacket.setTimePacket(date)
        
        #expect(packet.count == 16)
        #expect(packet[0] == ColmiCommand.setTime.rawValue)
        #expect(ColmiPacket.isValid(packet))
    }
    
    @Test("Real-time HR start/stop packets")
    func testRealTimePackets() {
        let start = RealTimeReading.startPacket(type: .heartRate)
        let stop = RealTimeReading.stopPacket(type: .heartRate)
        
        #expect(start[0] == ColmiCommand.realTimeHR.rawValue)
        #expect(start[1] == 0x01)  // Start flag
        #expect(start[2] == 0x00)  // HR type
        
        #expect(stop[0] == ColmiCommand.realTimeHR.rawValue)
        #expect(stop[1] == 0x00)   // Stop flag
        
        #expect(ColmiPacket.isValid(start))
        #expect(ColmiPacket.isValid(stop))
    }
    
    @Test("HR log request packet")
    func testHRLogRequest() {
        let date = Date(timeIntervalSince1970: 1710288000)
        let packet = HeartRateLogParser.requestPacket(for: date)
        
        #expect(packet[0] == ColmiCommand.readHeartRate.rawValue)
        #expect(ColmiPacket.isValid(packet))
        
        // Check timestamp bytes are present (bytes 1-4)
        // Verify some timestamp data was written
        let hasTimestampData = packet[1] != 0 || packet[2] != 0 || packet[3] != 0 || packet[4] != 0
        #expect(hasTimestampData)
    }
    
    @Test("Error packet detection")
    func testErrorPacket() {
        var packet = Data(count: 16)
        packet[0] = 0x83  // Battery command with error bit (0x80) set
        
        #expect(ColmiPacket.hasError(packet))
        #expect(ColmiPacket.commandType(packet) == .battery)
        
        packet[0] = 0x03  // No error
        #expect(!ColmiPacket.hasError(packet))
    }
    
    @Test("Activity request packet")
    func testActivityRequest() {
        let packet = ActivityParser.requestPacket(dayOffset: 0)
        
        #expect(packet[0] == ColmiCommand.readActivity.rawValue)
        #expect(packet[1] == 0x00)  // Day offset
        #expect(packet[2] == 0x0F)  // Constant
        #expect(ColmiPacket.isValid(packet))
        
        // Test with offset
        let yesterday = ActivityParser.requestPacket(dayOffset: 1)
        #expect(yesterday[1] == 0x01)
    }
    
    @Test("Activity parser - no data")
    func testActivityNoData() {
        let parser = ActivityParser()
        
        // No data packet: byte 1 = 0xFF
        var packet = Data(count: 16)
        packet[0] = ColmiCommand.readActivity.rawValue
        packet[1] = 0xFF  // No data
        packet[15] = ColmiPacket.checksum(packet)
        
        let result = parser.parse(packet)
        #expect(result != nil)
        #expect(result?.details.isEmpty == true)
    }
    
    @Test("Activity parser - header packet")
    func testActivityHeader() {
        let parser = ActivityParser()
        
        // Header packet: byte 1 = 0xF0
        var packet = Data(count: 16)
        packet[0] = ColmiCommand.readActivity.rawValue
        packet[1] = 0xF0  // Header marker
        packet[2] = 0x03  // 3 total packets
        packet[3] = 0x01  // New calorie protocol
        packet[15] = ColmiPacket.checksum(packet)
        
        // Header should return nil (waiting for more)
        let result = parser.parse(packet)
        #expect(result == nil)
    }
    
    @Test("SpO2 log request packet")
    func testSpO2LogRequest() {
        let date = Date(timeIntervalSince1970: 1710288000)
        let packet = SpO2LogParser.requestPacket(for: date)
        
        #expect(packet[0] == ColmiCommand.readSpO2Log.rawValue)
        #expect(ColmiPacket.isValid(packet))
    }
    
    @Test("SpO2 log parser - error response")
    func testSpO2LogError() {
        let parser = SpO2LogParser()
        
        var packet = Data(count: 16)
        packet[0] = ColmiCommand.readSpO2Log.rawValue
        packet[1] = 0xFF  // Error/no data
        packet[15] = ColmiPacket.checksum(packet)
        
        let result = parser.parse(packet)
        #expect(result == nil)
    }
    
    @Test("SportDetail properties")
    func testSportDetailTimeIndex() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 3
        components.day = 13
        components.hour = 14
        components.minute = 30
        
        guard let timestamp = calendar.date(from: components) else {
            Issue.record("Failed to create date")
            return
        }
        
        let detail = SportDetail(
            timestamp: timestamp,
            steps: 500,
            calories: 25,
            distance: 350
        )
        
        // 14:30 should be index 58 (14*4 + 30/15 = 56 + 2)
        #expect(detail.timeIndex == 58)
        #expect(detail.steps == 500)
        #expect(detail.calories == 25)
        #expect(detail.distance == 350)
    }
    
    @Test("DailyActivity totals")
    func testDailyActivityTotals() {
        let now = Date()
        let details = [
            SportDetail(timestamp: now, steps: 100, calories: 10, distance: 50),
            SportDetail(timestamp: now, steps: 200, calories: 20, distance: 100),
            SportDetail(timestamp: now, steps: 300, calories: 30, distance: 150)
        ]
        
        let activity = DailyActivity(date: now, details: details)
        
        #expect(activity.totalSteps == 600)
        #expect(activity.totalCalories == 60)
        #expect(activity.totalDistance == 300)
    }
}
