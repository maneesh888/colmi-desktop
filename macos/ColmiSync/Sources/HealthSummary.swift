import Foundation

/// Reads saved health data and prints a summary for Charles/AI integration
enum HealthSummary {
    
    private static let healthDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("clawd/health")
    
    /// Print a health summary for the last N days
    static func printSummary(days: Int = 7) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        
        let calendar = Calendar.current
        let today = Date()
        
        print("# Health Summary (last \(days) days)")
        print("")
        
        // Latest readings
        if let latest = loadLatest() {
            print("## Latest Readings")
            if let hr = latest["heartRate"] as? Int, let hrTime = latest["heartRateTime"] as? String {
                print("- Heart Rate: \(hr) BPM (\(formatTime(hrTime)))")
            }
            if let spo2 = latest["spO2"] as? Int, let spo2Time = latest["spO2Time"] as? String {
                print("- SpO2: \(spo2)% (\(formatTime(spo2Time)))")
            }
            if let battery = latest["battery"] as? Int {
                print("- Ring Battery: \(battery)%")
            }
            print("")
        }
        
        // Daily summaries
        print("## Daily Data")
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = df.string(from: date)
            
            var hasData = false
            var dayOutput = "\n### \(dateStr)\n"
            
            // Sleep
            if let sleep = loadSleep(dateStr: dateStr) {
                hasData = true
                let duration = sleep["durationFormatted"] as? String ?? "unknown"
                let quality = sleep["qualityScore"] as? Int ?? 0
                let deep = sleep["deepSleepMinutes"] as? Int ?? 0
                let light = sleep["lightSleepMinutes"] as? Int ?? 0
                let rem = sleep["remSleepMinutes"] as? Int ?? 0
                dayOutput += "- 😴 Sleep: \(duration), Quality: \(quality)%\n"
                dayOutput += "  - Deep: \(deep)m, Light: \(light)m, REM: \(rem)m\n"
            }
            
            // Activity
            if let activity = loadActivity(dateStr: dateStr) {
                if let steps = activity["totalSteps"] as? Int, steps > 0 {
                    hasData = true
                    let cal = activity["totalCalories"] as? Int ?? 0
                    let dist = activity["totalDistance"] as? Int ?? 0
                    dayOutput += "- 🚶 Steps: \(steps), Calories: \(cal), Distance: \(dist)m\n"
                }
            }
            
            // HR stats (from saved JSON)
            if let hr = loadHR(dateStr: dateStr) {
                if let readings = extractHRReadings(from: hr), !readings.isEmpty {
                    hasData = true
                    let avg = readings.reduce(0, +) / readings.count
                    let min = readings.min() ?? 0
                    let max = readings.max() ?? 0
                    dayOutput += "- ❤️ HR: avg \(avg), min \(min), max \(max) BPM (\(readings.count) readings)\n"
                }
            }
            
            // Stress
            if let stress = loadStress(dateStr: dateStr) {
                if let readings = stress["readings"] as? [Int] {
                    let valid = readings.filter { $0 > 0 && $0 <= 100 }
                    if !valid.isEmpty {
                        hasData = true
                        let avg = valid.reduce(0, +) / valid.count
                        dayOutput += "- 😰 Stress: avg \(avg) (\(valid.count) readings)\n"
                    }
                }
            }
            
            if hasData {
                print(dayOutput, terminator: "")
            }
        }
        
        print("\n---")
        print("Data from: ~/clawd/health/")
    }
    
    // MARK: - Data Loading
    
    private static func loadLatest() -> [String: Any]? {
        let file = healthDir.appendingPathComponent("latest.json")
        return loadJSON(file)
    }
    
    private static func loadSleep(dateStr: String) -> [String: Any]? {
        let file = healthDir.appendingPathComponent("sleep-\(dateStr).json")
        return loadJSON(file)
    }
    
    private static func loadActivity(dateStr: String) -> [String: Any]? {
        let file = healthDir.appendingPathComponent("activity-\(dateStr).json")
        return loadJSON(file)
    }
    
    private static func loadHR(dateStr: String) -> [String: Any]? {
        let file = healthDir.appendingPathComponent("hr-\(dateStr).json")
        return loadJSON(file)
    }
    
    private static func loadStress(dateStr: String) -> [String: Any]? {
        let file = healthDir.appendingPathComponent("stress-\(dateStr).json")
        return loadJSON(file)
    }
    
    private static func loadJSON(_ file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
    
    private static func extractHRReadings(from hr: [String: Any]) -> [Int]? {
        // Handle both formats: array of ints or array of {bpm, timestamp}
        if let readings = hr["readings"] as? [Int] {
            return readings.filter { $0 > 0 && $0 <= 200 }
        }
        if let readings = hr["readings"] as? [[String: Any]] {
            return readings.compactMap { $0["bpm"] as? Int }.filter { $0 > 0 && $0 <= 200 }
        }
        return nil
    }
    
    private static func formatTime(_ isoTime: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: isoTime) else { return isoTime }
        
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        df.timeZone = .current
        return df.string(from: date)
    }
}
