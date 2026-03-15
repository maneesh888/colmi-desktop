import Testing
import Foundation
@testable import ColmiBLE

@Suite("ColmiBLE Tests")
struct ColmiBLETests {
    
    @Test("Ring info initialization")
    func testRingInfo() {
        let info = RingInfo(
            id: UUID(),
            name: "R09_1234",
            rssi: -65
        )
        
        #expect(info.name == "R09_1234")
        #expect(info.rssi == -65)
    }
    
    @Test("Connection state enum")
    func testConnectionState() {
        let state: RingConnectionState = .disconnected
        #expect(state == .disconnected)
    }
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        #expect(ColmiError.notConnected.errorDescription != nil)
        #expect(ColmiError.timeout.errorDescription != nil)
        #expect(ColmiError.ringNotFound.errorDescription != nil)
    }
}
