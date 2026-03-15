import Foundation

/// Utilities for building and parsing 16-byte Colmi packets
public enum ColmiPacket {
    
    /// Packet size (all Colmi packets are 16 bytes)
    public static let size = 16
    
    /// Create a 16-byte packet with command, optional payload, and checksum
    public static func make(command: ColmiCommand, payload: Data = Data()) -> Data {
        var packet = Data(count: size)
        packet[0] = command.rawValue
        
        // Copy payload (max 14 bytes, leaving room for command and checksum)
        let payloadBytes = min(payload.count, 14)
        if payloadBytes > 0 {
            packet.replaceSubrange(1..<(1 + payloadBytes), with: payload.prefix(payloadBytes))
        }
        
        // Calculate and set checksum (last byte)
        packet[15] = checksum(packet)
        
        return packet
    }
    
    /// Create a raw packet with command byte
    public static func make(commandByte: UInt8, payload: Data = Data()) -> Data {
        var packet = Data(count: size)
        packet[0] = commandByte
        
        let payloadBytes = min(payload.count, 14)
        if payloadBytes > 0 {
            packet.replaceSubrange(1..<(1 + payloadBytes), with: payload.prefix(payloadBytes))
        }
        
        packet[15] = checksum(packet)
        return packet
    }
    
    /// Calculate checksum: sum of first 15 bytes mod 256
    public static func checksum(_ data: Data) -> UInt8 {
        let sum = data.prefix(15).reduce(0) { $0 + UInt16($1) }
        return UInt8(sum & 0xFF)
    }
    
    /// Validate packet checksum
    public static func isValid(_ data: Data) -> Bool {
        guard data.count == size else { return false }
        return data[15] == checksum(data)
    }
    
    /// Get command type from packet
    public static func commandType(_ data: Data) -> ColmiCommand? {
        guard data.count >= 1 else { return nil }
        // Mask the error bit (0x80) to get command
        return ColmiCommand(rawValue: data[0] & 0x7F)
    }
    
    /// Get raw command byte from packet
    public static func commandByte(_ data: Data) -> UInt8? {
        guard data.count >= 1 else { return nil }
        return data[0] & 0x7F
    }
    
    /// Check if packet has error bit set
    public static func hasError(_ data: Data) -> Bool {
        guard data.count >= 1 else { return true }
        return (data[0] & 0x80) != 0
    }
    
    /// Get subtype byte (byte 1) from packet
    public static func subtype(_ data: Data) -> UInt8? {
        guard data.count >= 2 else { return nil }
        return data[1]
    }
    
    /// Get payload data (bytes 1-14)
    public static func payload(_ data: Data) -> Data {
        guard data.count >= 15 else { return Data() }
        return data[1..<15]
    }
    
    /// Format packet as hex string for debugging
    public static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// MARK: - Timestamp Utilities

extension ColmiPacket {
    /// Create Unix timestamp bytes (little-endian UInt32)
    public static func timestampBytes(for date: Date) -> Data {
        let timestamp = UInt32(clamping: Int64(max(0, date.timeIntervalSince1970)))
        var bytes = Data(count: 4)
        bytes.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: timestamp.littleEndian, as: UInt32.self)
        }
        return bytes
    }
    
    /// Parse Unix timestamp from bytes (little-endian UInt32)
    public static func parseTimestamp(_ data: Data, offset: Int = 0) -> Date? {
        guard data.count >= offset + 4 else { return nil }
        let timestamp = data[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}
