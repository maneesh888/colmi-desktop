import Foundation

// MARK: - Sleep Inference Engine

/// Infers sleep sessions from heart rate and activity data.
/// Used when the ring doesn't support direct sleep data (0xBC command).
///
/// Algorithm overview:
/// 1. Analyze overnight period (default: 8 PM to 10 AM)
/// 2. Find sleep onset: sustained low HR with low variability
/// 3. Find wake time: HR increases with higher variability
/// 4. Classify stages based on HR characteristics:
///    - Deep: lowest HR (typically 10-20% below resting), low variability
///    - REM: HR closer to waking, higher variability, irregular patterns
///    - Light: moderate HR, moderate variability
///    - Awake: periods of elevated HR during sleep window
public struct SleepInferenceEngine: Sendable {
    
    // Configuration
    public struct Config: Sendable {
        /// Start of overnight window (hour, 0-23)
        public var overnightStartHour: Int = 20  // 8 PM
        
        /// End of overnight window (hour, 0-23)
        public var overnightEndHour: Int = 10    // 10 AM
        
        /// Minimum consecutive low-HR readings to consider as sleep (5-min intervals)
        public var minSleepReadings: Int = 12    // 1 hour
        
        /// HR drop threshold below resting to consider sleeping (percentage)
        public var sleepHRDropPercent: Double = 0.10  // 10%
        
        /// Deep sleep HR drop threshold (percentage below sleep avg)
        public var deepSleepHRDropPercent: Double = 0.15  // 15%
        
        /// HR variability threshold for sleep detection (BPM)
        public var maxSleepVariability: Double = 8.0
        
        /// Minimum sleep session duration (minutes)
        public var minSleepDurationMinutes: Int = 30
        
        public init() {}
    }
    
    public let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Infer sleep session from heart rate data for a specific night.
    /// - Parameters:
    ///   - hrLogs: Heart rate logs (should include evening before and morning of sleep)
    ///   - date: The date to analyze (the morning/wake date)
    /// - Returns: Inferred sleep session, or nil if no sleep detected
    public func inferSleep(from hrLogs: [HeartRateLog], for date: Date) -> SleepSession? {
        // Get overnight readings
        let overnight = getOvernightReadings(from: hrLogs, for: date)
        guard overnight.count >= config.minSleepReadings else { return nil }
        
        // Calculate baseline/resting HR
        let restingHR = calculateRestingHR(from: hrLogs)
        guard restingHR > 0 else { return nil }
        
        // Find sleep period
        guard let (sleepStart, sleepEnd) = detectSleepWindow(
            readings: overnight,
            restingHR: restingHR
        ) else { return nil }
        
        // Classify stages
        let stages = classifySleepStages(
            readings: Array(overnight[sleepStart...sleepEnd]),
            startTime: overnight[sleepStart].time,
            restingHR: restingHR
        )
        
        guard !stages.isEmpty else { return nil }
        
        return SleepSession(
            startTime: overnight[sleepStart].time,
            endTime: overnight[sleepEnd].time,
            stages: stages
        )
    }
    
    /// Calculate sleep quality score (0-100)
    public func calculateQualityScore(_ session: SleepSession) -> Int {
        let totalMinutes = session.durationMinutes
        guard totalMinutes > 0 else { return 0 }
        
        // Ideal sleep duration: 7-9 hours
        let durationScore: Double
        let hours = Double(totalMinutes) / 60.0
        if hours >= 7 && hours <= 9 {
            durationScore = 1.0
        } else if hours >= 6 && hours < 7 {
            durationScore = 0.8
        } else if hours > 9 && hours <= 10 {
            durationScore = 0.9
        } else if hours >= 5 && hours < 6 {
            durationScore = 0.6
        } else {
            durationScore = 0.4
        }
        
        // Deep sleep should be 15-20% of total
        let deepPercent = Double(session.deepSleepMinutes) / Double(totalMinutes)
        let deepScore = min(1.0, deepPercent / 0.15)
        
        // REM should be 20-25% of total
        let remPercent = Double(session.remSleepMinutes) / Double(totalMinutes)
        let remScore = min(1.0, remPercent / 0.20)
        
        // Awake time should be minimal
        let awakePercent = Double(session.awakeMinutes) / Double(totalMinutes)
        let awakeScore = max(0, 1.0 - (awakePercent * 5))  // Penalize heavily
        
        // Weighted average
        let score = (durationScore * 0.3 + deepScore * 0.3 + remScore * 0.25 + awakeScore * 0.15) * 100
        return min(100, max(0, Int(score)))
    }
    
    // MARK: - Private Methods
    
    private func getOvernightReadings(from hrLogs: [HeartRateLog], for date: Date) -> [(time: Date, bpm: Int)] {
        let calendar = Calendar.current
        
        // Get evening before (previous day)
        let eveningDate = calendar.date(byAdding: .day, value: -1, to: date)!
        let eveningStart = calendar.date(bySettingHour: config.overnightStartHour, minute: 0, second: 0, of: eveningDate)!
        
        // Get morning of
        let morningEnd = calendar.date(bySettingHour: config.overnightEndHour, minute: 0, second: 0, of: date)!
        
        // Collect readings in range
        var readings: [(time: Date, bpm: Int)] = []
        
        for log in hrLogs {
            for (time, bpm) in log.readingsWithTimes {
                if time >= eveningStart && time <= morningEnd {
                    readings.append((time, bpm))
                }
            }
        }
        
        return readings.sorted { $0.time < $1.time }
    }
    
    private func calculateRestingHR(from hrLogs: [HeartRateLog]) -> Double {
        // Use lowest 10% of valid readings as resting estimate
        let allReadings = hrLogs.flatMap { $0.validReadings }
        guard !allReadings.isEmpty else { return 0 }
        
        let sorted = allReadings.sorted()
        let count = max(1, sorted.count / 10)
        let lowest = Array(sorted.prefix(count))
        
        return Double(lowest.reduce(0, +)) / Double(lowest.count)
    }
    
    private func detectSleepWindow(readings: [(time: Date, bpm: Int)], restingHR: Double) -> (start: Int, end: Int)? {
        guard readings.count >= config.minSleepReadings else { return nil }
        
        let sleepThreshold = restingHR * (1 - config.sleepHRDropPercent)
        
        // Find first sustained period of low HR
        var sleepStart: Int?
        var consecutiveLow = 0
        
        for i in 0..<readings.count {
            if Double(readings[i].bpm) <= sleepThreshold {
                consecutiveLow += 1
                if consecutiveLow >= config.minSleepReadings && sleepStart == nil {
                    sleepStart = i - consecutiveLow + 1
                }
            } else {
                if sleepStart == nil {
                    consecutiveLow = 0
                }
            }
        }
        
        guard let start = sleepStart else { return nil }
        
        // Find wake time: sustained increase above threshold
        var sleepEnd = readings.count - 1
        consecutiveLow = 0
        
        for i in (start..<readings.count).reversed() {
            if Double(readings[i].bpm) <= sleepThreshold {
                consecutiveLow += 1
                if consecutiveLow >= 3 {  // 15 minutes of low HR
                    sleepEnd = i + consecutiveLow - 1
                    break
                }
            } else {
                consecutiveLow = 0
            }
        }
        
        // Validate minimum duration
        let durationMinutes = (sleepEnd - start) * 5
        guard durationMinutes >= config.minSleepDurationMinutes else { return nil }
        
        return (start, min(sleepEnd, readings.count - 1))
    }
    
    private func classifySleepStages(
        readings: [(time: Date, bpm: Int)],
        startTime: Date,
        restingHR: Double
    ) -> [SleepStageRecord] {
        guard readings.count >= 6 else { return [] }  // At least 30 minutes
        
        var stages: [SleepStageRecord] = []
        let calendar = Calendar.current
        
        // Calculate sleep average
        let sleepAvgHR = Double(readings.map { $0.bpm }.reduce(0, +)) / Double(readings.count)
        let deepThreshold = sleepAvgHR * (1 - config.deepSleepHRDropPercent)
        
        // Process in 30-minute windows for stage classification
        let windowSize = 6  // 6 readings = 30 minutes
        var i = 0
        
        while i < readings.count {
            let windowEnd = min(i + windowSize, readings.count)
            let window = Array(readings[i..<windowEnd])
            
            let stage = classifyWindow(
                window: window,
                sleepAvgHR: sleepAvgHR,
                deepThreshold: deepThreshold,
                restingHR: restingHR
            )
            
            let stageStart = calendar.date(byAdding: .minute, value: i * 5, to: startTime)!
            let duration = (windowEnd - i) * 5
            
            // Merge with previous if same stage
            if let last = stages.last, last.stage == stage {
                stages[stages.count - 1] = SleepStageRecord(
                    startTime: last.startTime,
                    stage: stage,
                    durationMinutes: last.durationMinutes + duration
                )
            } else {
                stages.append(SleepStageRecord(
                    startTime: stageStart,
                    stage: stage,
                    durationMinutes: duration
                ))
            }
            
            i = windowEnd
        }
        
        return stages
    }
    
    private func classifyWindow(
        window: [(time: Date, bpm: Int)],
        sleepAvgHR: Double,
        deepThreshold: Double,
        restingHR: Double
    ) -> SleepStage {
        let hrs = window.map { Double($0.bpm) }
        let avgHR = hrs.reduce(0, +) / Double(hrs.count)
        
        // Calculate variability (standard deviation)
        let variance = hrs.map { pow($0 - avgHR, 2) }.reduce(0, +) / Double(hrs.count)
        let stdDev = sqrt(variance)
        
        // High HR or high variability = awake
        if avgHR > restingHR * 0.95 || stdDev > 15 {
            return .awake
        }
        
        // Very low HR + low variability = deep sleep
        if avgHR <= deepThreshold && stdDev < 5 {
            return .deep
        }
        
        // Moderate HR + higher variability = REM
        // REM typically has HR closer to waking with irregular patterns
        if stdDev > 8 && avgHR > deepThreshold * 0.95 {
            return .rem
        }
        
        // Default: light sleep
        return .light
    }
}

// MARK: - Extensions

extension SleepSession {
    /// Create session from inference engine
    public static func inferred(from hrLogs: [HeartRateLog], for date: Date, using engine: SleepInferenceEngine = SleepInferenceEngine()) -> SleepSession? {
        engine.inferSleep(from: hrLogs, for: date)
    }
}
