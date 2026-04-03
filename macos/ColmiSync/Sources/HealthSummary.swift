import Foundation

/// Reads saved health data and prints a summary for Charles/AI integration
enum HealthSummary {
    
    private static let healthDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("clawd/health")
    
    /// Print a health summary for the last N days (JSON format for AI consumption)
    static func printSummaryJSON(days: Int = 7) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        
        let calendar = Calendar.current
        let today = Date()
        
        var summary: [String: Any] = [
            "generated": ISO8601DateFormatter().string(from: Date()),
            "days": days
        ]
        
        // Latest readings
        if let latest = loadLatest() {
            var latestData: [String: Any] = [:]
            if let hr = latest["heartRate"] as? Int, let hrTime = latest["heartRateTime"] as? String {
                latestData["heartRate"] = ["value": hr, "time": hrTime]
            }
            if let spo2 = latest["spO2"] as? Int, let spo2Time = latest["spO2Time"] as? String {
                latestData["spO2"] = ["value": spo2, "time": spo2Time]
            }
            if let battery = latest["battery"] as? Int {
                latestData["battery"] = battery
            }
            if !latestData.isEmpty {
                summary["latest"] = latestData
            }
        }
        
        // Daily data
        var dailyData: [[String: Any]] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = df.string(from: date)
            
            var dayData: [String: Any] = ["date": dateStr]
            
            // Sleep
            if let sleep = loadSleep(dateStr: dateStr) {
                dayData["sleep"] = [
                    "durationMinutes": sleep["durationMinutes"] as? Int ?? 0,
                    "durationFormatted": sleep["durationFormatted"] as? String ?? "",
                    "qualityScore": sleep["qualityScore"] as? Int ?? 0,
                    "deepSleepMinutes": sleep["deepSleepMinutes"] as? Int ?? 0,
                    "lightSleepMinutes": sleep["lightSleepMinutes"] as? Int ?? 0,
                    "remSleepMinutes": sleep["remSleepMinutes"] as? Int ?? 0,
                    "awakeMinutes": sleep["awakeMinutes"] as? Int ?? 0
                ]
            }
            
            // Activity
            if let activity = loadActivity(dateStr: dateStr) {
                if let steps = activity["totalSteps"] as? Int, steps > 0 {
                    dayData["activity"] = [
                        "steps": steps,
                        "calories": activity["totalCalories"] as? Int ?? 0,
                        "distance": activity["totalDistance"] as? Int ?? 0
                    ]
                }
            }
            
            // HR stats
            if let hr = loadHR(dateStr: dateStr) {
                if let readings = extractHRReadings(from: hr), !readings.isEmpty {
                    let avg = readings.reduce(0, +) / readings.count
                    dayData["heartRate"] = [
                        "avg": avg,
                        "min": readings.min() ?? 0,
                        "max": readings.max() ?? 0,
                        "count": readings.count
                    ]
                }
            }
            
            // Stress
            if let stress = loadStress(dateStr: dateStr) {
                if let readings = stress["readings"] as? [Int] {
                    let valid = readings.filter { $0 > 0 && $0 <= 100 }
                    if !valid.isEmpty {
                        let avg = valid.reduce(0, +) / valid.count
                        dayData["stress"] = [
                            "avg": avg,
                            "count": valid.count
                        ]
                    }
                }
            }
            
            // Only add days with data
            if dayData.keys.count > 1 {
                dailyData.append(dayData)
            }
        }
        
        summary["daily"] = dailyData
        
        // Calculate weekly trends
        if !dailyData.isEmpty {
            var trends: [String: Any] = [:]
            
            // Steps trend
            let stepsData = dailyData.compactMap { ($0["activity"] as? [String: Any])?["steps"] as? Int }
            if stepsData.count >= 2 {
                let avgSteps = stepsData.reduce(0, +) / stepsData.count
                trends["avgSteps"] = avgSteps
                trends["totalSteps"] = stepsData.reduce(0, +)
            }
            
            // HR trend
            let hrData = dailyData.compactMap { ($0["heartRate"] as? [String: Any])?["avg"] as? Int }
            if hrData.count >= 2 {
                let avgHR = hrData.reduce(0, +) / hrData.count
                let minHR = hrData.min() ?? 0
                let maxHR = hrData.max() ?? 0
                trends["avgRestingHR"] = avgHR
                trends["hrRange"] = ["min": minHR, "max": maxHR]
            }
            
            // Sleep trend
            let sleepData = dailyData.compactMap { ($0["sleep"] as? [String: Any])?["durationMinutes"] as? Int }
            if sleepData.count >= 2 {
                let avgSleep = sleepData.reduce(0, +) / sleepData.count
                trends["avgSleepMinutes"] = avgSleep
                trends["avgSleepFormatted"] = "\(avgSleep / 60)h \(avgSleep % 60)m"
            }
            
            let qualityData = dailyData.compactMap { ($0["sleep"] as? [String: Any])?["qualityScore"] as? Int }
            if qualityData.count >= 2 {
                trends["avgSleepQuality"] = qualityData.reduce(0, +) / qualityData.count
            }
            
            if !trends.isEmpty {
                summary["weeklyTrends"] = trends
            }
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            print(String(data: jsonData, encoding: .utf8) ?? "{}")
        } else {
            print("{}")
        }
    }
    
    /// Print a health summary for the last N days (markdown format)
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
        
        // Weekly trends
        var stepsData: [Int] = []
        var hrData: [Int] = []
        var sleepData: [Int] = []
        var qualityData: [Int] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = df.string(from: date)
            
            if let activity = loadActivity(dateStr: dateStr),
               let steps = activity["totalSteps"] as? Int, steps > 0 {
                stepsData.append(steps)
            }
            if let hr = loadHR(dateStr: dateStr),
               let readings = extractHRReadings(from: hr), !readings.isEmpty {
                hrData.append(readings.reduce(0, +) / readings.count)
            }
            if let sleep = loadSleep(dateStr: dateStr) {
                if let duration = sleep["durationMinutes"] as? Int, duration > 0 {
                    sleepData.append(duration)
                }
                if let quality = sleep["qualityScore"] as? Int, quality > 0 {
                    qualityData.append(quality)
                }
            }
        }
        
        if !stepsData.isEmpty || !hrData.isEmpty || !sleepData.isEmpty {
            print("\n## Weekly Trends")
            if !stepsData.isEmpty {
                let avg = stepsData.reduce(0, +) / stepsData.count
                let total = stepsData.reduce(0, +)
                print("- 🚶 Avg Steps: \(avg)/day, Total: \(total)")
            }
            if !hrData.isEmpty {
                let avg = hrData.reduce(0, +) / hrData.count
                print("- ❤️ Avg Resting HR: \(avg) BPM")
            }
            if !sleepData.isEmpty {
                let avg = sleepData.reduce(0, +) / sleepData.count
                print("- 😴 Avg Sleep: \(avg / 60)h \(avg % 60)m")
            }
            if !qualityData.isEmpty {
                let avg = qualityData.reduce(0, +) / qualityData.count
                print("- 🌟 Avg Sleep Quality: \(avg)%")
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
