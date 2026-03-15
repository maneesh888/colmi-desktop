import Foundation

// MARK: - Sleep Session

/// A single sleep session
public struct SleepSession: Codable, Sendable, Equatable {
    public let startTime: Date
    public let endTime: Date
    public let stages: [SleepStageRecord]
    
    public init(startTime: Date, endTime: Date, stages: [SleepStageRecord]) {
        self.startTime = startTime
        self.endTime = endTime
        self.stages = stages
    }
    
    /// Total sleep duration in minutes
    public var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }
    
    /// Duration in hours and minutes
    public var durationFormatted: String {
        let hours = durationMinutes / 60
        let mins = durationMinutes % 60
        return "\(hours)h \(mins)m"
    }
    
    /// Time spent in each stage (minutes)
    public var lightSleepMinutes: Int {
        stages.filter { $0.stage == .light }.reduce(0) { $0 + $1.durationMinutes }
    }
    
    public var deepSleepMinutes: Int {
        stages.filter { $0.stage == .deep }.reduce(0) { $0 + $1.durationMinutes }
    }
    
    public var remSleepMinutes: Int {
        stages.filter { $0.stage == .rem }.reduce(0) { $0 + $1.durationMinutes }
    }
    
    public var awakeMinutes: Int {
        stages.filter { $0.stage == .awake }.reduce(0) { $0 + $1.durationMinutes }
    }
    
    /// Sleep quality score (0-100)
    public var qualityScore: Int {
        let total = durationMinutes
        guard total > 0 else { return 0 }
        
        // Simple scoring: deep + REM is good, awake is bad
        let goodSleep = deepSleepMinutes + remSleepMinutes
        let score = Int(Double(goodSleep) / Double(total) * 100)
        return min(100, max(0, score))
    }
}

/// A single sleep stage record
public struct SleepStageRecord: Codable, Sendable, Equatable {
    public let startTime: Date
    public let stage: SleepStage
    public let durationMinutes: Int
    
    public init(startTime: Date, stage: SleepStage, durationMinutes: Int) {
        self.startTime = startTime
        self.stage = stage
        self.durationMinutes = durationMinutes
    }
}

// MARK: - Sleep Parser

/// Parser for sleep data from Big Data V2 command
public final class SleepParser: @unchecked Sendable {
    
    public init() {}
    
    /// Parse sleep data packet
    /// Returns array of sleep sessions
    public func parse(_ data: Data) -> [SleepSession]? {
        guard data.count >= 7,
              data[0] == ColmiCommand.bigDataV2.rawValue,
              data[1] == BigDataType.sleep.rawValue else {
            return nil
        }
        
        // Packet length
        let packetLength = Int(data[2]) | (Int(data[3]) << 8)
        guard packetLength >= 2 else { return [] }
        
        // Number of days in packet
        let daysInPacket = Int(data[6])
        guard daysInPacket > 0 else { return [] }
        
        var sessions: [SleepSession] = []
        var index = 7
        
        for _ in 1...daysInPacket {
            guard index + 6 <= data.count else { break }
            
            let daysAgo = Int(data[index])
            index += 1
            
            let dayBytes = Int(data[index])
            index += 1
            
            // Sleep start/end as minutes after midnight
            let sleepStart = Int(data[index]) | (Int(data[index + 1]) << 8)
            index += 2
            
            let sleepEnd = Int(data[index]) | (Int(data[index + 1]) << 8)
            index += 2
            
            // Calculate timestamps
            let calendar = Calendar.current
            var sessionStartDate = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            sessionStartDate = calendar.startOfDay(for: sessionStartDate)
            
            // If sleep started before midnight
            if sleepStart > sleepEnd {
                sessionStartDate = calendar.date(byAdding: .minute, value: sleepStart - 1440, to: sessionStartDate)!
            } else {
                sessionStartDate = calendar.date(byAdding: .minute, value: sleepStart, to: sessionStartDate)!
            }
            
            var sessionEndDate = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            sessionEndDate = calendar.startOfDay(for: sessionEndDate)
            sessionEndDate = calendar.date(byAdding: .minute, value: sleepEnd, to: sessionEndDate)!
            
            // Parse sleep stages
            var stages: [SleepStageRecord] = []
            var stageTime = sessionStartDate
            
            // Stage data starts at index, each stage is 2 bytes (type, duration)
            let stageDataEnd = index + dayBytes - 4  // -4 for the bytes we already read
            while index + 1 < stageDataEnd && index + 1 < data.count {
                let stageType = data[index]
                let stageDuration = Int(data[index + 1])
                index += 2
                
                if stageDuration > 0, let stage = SleepStage(rawValue: stageType) {
                    stages.append(SleepStageRecord(
                        startTime: stageTime,
                        stage: stage,
                        durationMinutes: stageDuration
                    ))
                    stageTime = calendar.date(byAdding: .minute, value: stageDuration, to: stageTime)!
                }
            }
            
            sessions.append(SleepSession(
                startTime: sessionStartDate,
                endTime: sessionEndDate,
                stages: stages
            ))
        }
        
        return sessions
    }
    
    /// Request packet for sleep data
    public static var requestPacket: Data {
        var packet = Data(count: 16)
        packet[0] = ColmiCommand.bigDataV2.rawValue
        packet[1] = BigDataType.sleep.rawValue
        packet[2] = 0x01
        packet[3] = 0x00
        packet[4] = 0xff
        packet[5] = 0x00
        packet[6] = 0xff
        packet[15] = ColmiPacket.checksum(packet)
        return packet
    }
}
