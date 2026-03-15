import Testing
@testable import ColmiProtocol

@Suite("Packet Tests")
struct PacketTests {
    
    @Test("Packet checksum calculation")
    func testChecksum() {
        var packet = Data(count: 16)
        packet[0] = 0x03  // Battery command
        let checksum = ColmiPacket.checksum(packet)
        #expect(checksum == 0x03)
    }
    
    @Test("Packet creation with command")
    func testMakePacket() {
        let packet = ColmiPacket.make(command: .battery)
        #expect(packet.count == 16)
        #expect(packet[0] == ColmiCommand.battery.rawValue)
        #expect(ColmiPacket.isValid(packet))
    }
    
    @Test("Packet creation with payload")
    func testMakePacketWithPayload() {
        let payload = Data([0x01, 0x02, 0x03])
        let packet = ColmiPacket.make(command: .hrLogSettings, payload: payload)
        #expect(packet[0] == ColmiCommand.hrLogSettings.rawValue)
        #expect(packet[1] == 0x01)
        #expect(packet[2] == 0x02)
        #expect(packet[3] == 0x03)
        #expect(ColmiPacket.isValid(packet))
    }
    
    @Test("Command type extraction")
    func testCommandType() {
        let packet = ColmiPacket.make(command: .readHeartRate)
        let cmd = ColmiPacket.commandType(packet)
        #expect(cmd == .readHeartRate)
    }
    
    @Test("Error bit detection")
    func testErrorBit() {
        var packet = ColmiPacket.make(command: .battery)
        #expect(!ColmiPacket.hasError(packet))
        
        packet[0] = 0x83  // Battery with error bit
        #expect(ColmiPacket.hasError(packet))
    }
    
    @Test("Timestamp bytes creation")
    func testTimestampBytes() {
        let date = Date(timeIntervalSince1970: 1234567890)
        let bytes = ColmiPacket.timestampBytes(for: date)
        #expect(bytes.count == 4)
        
        // Parse it back
        let parsed = ColmiPacket.parseTimestamp(bytes)
        #expect(parsed != nil)
        #expect(Int(parsed!.timeIntervalSince1970) == 1234567890)
    }
}
