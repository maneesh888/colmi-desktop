import Foundation
import os

/// Local storage for health data
actor DataStore {
    static let shared = DataStore()
    
    private let logger = Logger(subsystem: "com.colmisync", category: "DataStore")
    private let baseURL: URL
    
    private init() {
        // Store in ~/clawd/health/
        baseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
    
    // MARK: - Heart Rate
    
    func saveHeartRateLog(_ log: HeartRateLog) throws {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let filename = "hr-\(dateFormatter.string(from: log.date)).json"
        let url = baseURL.appendingPathComponent(filename)
        
        let data = HeartRateFileData(
            date: log.date,
            readings: log.readingsWithTimes.map { 
                HeartRateReading(timestamp: $0.time, bpm: $0.bpm) 
            }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
        
        logger.info("Saved HR log to \(filename)")
    }
    
    func loadHeartRateLogs(from: Date, to: Date) throws -> [HeartRateFileData] {
        let files = try FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)
        let hrFiles = files.filter { $0.lastPathComponent.hasPrefix("hr-") }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return hrFiles.compactMap { url -> HeartRateFileData? in
            guard let data = try? Data(contentsOf: url),
                  let log = try? decoder.decode(HeartRateFileData.self, from: data),
                  log.date >= from && log.date <= to else {
                return nil
            }
            return log
        }
    }
    
    // MARK: - Activity/Steps
    
    func saveActivity(_ activity: DailyActivity) throws {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let filename = "activity-\(dateFormatter.string(from: activity.date)).json"
        let url = baseURL.appendingPathComponent(filename)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(activity)
        try jsonData.write(to: url)
        
        logger.info("Saved activity to \(filename)")
    }
    
    func loadActivity(for date: Date) throws -> DailyActivity? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let filename = "activity-\(dateFormatter.string(from: date)).json"
        let url = baseURL.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(DailyActivity.self, from: data)
    }
    
    // MARK: - SpO2 Logs
    
    func saveSpO2Log(_ log: SpO2Log) throws {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let filename = "spo2-\(dateFormatter.string(from: log.date)).json"
        let url = baseURL.appendingPathComponent(filename)
        
        let data = SpO2FileData(
            date: log.date,
            readings: log.readingsWithTimes.map { 
                SpO2ReadingData(timestamp: $0.time, value: $0.spO2) 
            }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
        
        logger.info("Saved SpO2 log to \(filename)")
    }
    
    // MARK: - Latest Readings
    
    func saveLatestReading(heartRate: Int? = nil, spO2: Int? = nil, battery: Int? = nil) throws {
        let url = baseURL.appendingPathComponent("latest.json")
        
        var latest = (try? loadLatestReading()) ?? LatestReadings()
        
        if let hr = heartRate {
            latest.heartRate = hr
            latest.heartRateTime = Date()
        }
        if let spo2 = spO2 {
            latest.spO2 = spo2
            latest.spO2Time = Date()
        }
        if let batt = battery {
            latest.battery = batt
            latest.batteryTime = Date()
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        
        let data = try encoder.encode(latest)
        try data.write(to: url)
    }
    
    func loadLatestReading() throws -> LatestReadings {
        let url = baseURL.appendingPathComponent("latest.json")
        let data = try Data(contentsOf: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(LatestReadings.self, from: data)
    }
}

// MARK: - Data Models

struct HeartRateFileData: Codable {
    let date: Date
    let readings: [HeartRateReading]
}

struct HeartRateReading: Codable {
    let timestamp: Date
    let bpm: Int
}

struct LatestReadings: Codable {
    var heartRate: Int?
    var heartRateTime: Date?
    var spO2: Int?
    var spO2Time: Date?
    var battery: Int?
    var batteryTime: Date?
    var steps: Int?
    var stepsTime: Date?
}

struct SpO2FileData: Codable {
    let date: Date
    let readings: [SpO2ReadingData]
}

struct SpO2ReadingData: Codable {
    let timestamp: Date
    let value: Int
}
