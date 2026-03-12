import Testing
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
        
        // Check timestamp is embedded correctly (little-endian)
        let embedded = packet[1..<5].withUnsafeBytes { $0.load(as: UInt32.self) }
        // Should be start of day for the given date
        #expect(embedded > 0)
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
}
