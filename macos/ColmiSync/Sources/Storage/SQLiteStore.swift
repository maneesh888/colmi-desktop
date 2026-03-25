import Foundation
import SQLite3
import os
import ColmiProtocol

// Type aliases to disambiguate local vs ColmiProtocol types
// Local types (from Protocol/ColmiProtocol.swift) are used for most data
// ColmiProtocol package types are used for Sleep since no local version exists
typealias CPSleepSession = ColmiProtocol.SleepSession
typealias CPSleepStage = ColmiProtocol.SleepStage

/// SQLite storage for health data
/// Schema compatible with colmi_r02_client for interoperability
actor SQLiteStore {
    private let logger = Logger(subsystem: "com.colmisync", category: "SQLiteStore")
    private var db: OpaquePointer?
    private let dbPath: URL
    
    private var ringId: Int64?
    private var currentSyncId: Int64?
    
    /// Create a new SQLiteStore. Use the async `open()` factory method instead.
    private init(dbPath: URL, db: OpaquePointer) {
        self.dbPath = dbPath
        self.db = db
    }
    
    /// Factory method to create and initialize SQLiteStore
    static func open(path: URL? = nil) async throws -> SQLiteStore {
        let dbPath = path ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("clawd/health/colmi.db")
        
        // Ensure directory exists
        let dir = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Open database
        var db: OpaquePointer?
        if sqlite3_open(dbPath.path, &db) != SQLITE_OK {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown error"
            throw SQLiteError.openFailed(msg)
        }
        
        let store = SQLiteStore(dbPath: dbPath, db: db!)
        await store.initialize()
        return store
    }
    
    private func initialize() {
        // Enable foreign keys
        execute("PRAGMA foreign_keys = ON")
        
        // Create schema
        createSchema()
        
        logger.info("SQLite database opened at \(self.dbPath.path)")
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Schema
    
    private func createSchema() {
        // Version table for migrations
        execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY
            )
        """)
        
        let version = getSchemaVersion()
        if version == 0 {
            migrateV1()
        }
    }
    
    private func getSchemaVersion() -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_version", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
        }
        return 0
    }
    
    private func migrateV1() {
        logger.info("Running schema migration v1")
        
        // Rings table (compatible with colmi_r02_client)
        execute("""
            CREATE TABLE IF NOT EXISTS rings (
                ring_id INTEGER PRIMARY KEY AUTOINCREMENT,
                address TEXT NOT NULL UNIQUE
            )
        """)
        
        // Syncs table
        execute("""
            CREATE TABLE IF NOT EXISTS syncs (
                sync_id INTEGER PRIMARY KEY AUTOINCREMENT,
                ring_id INTEGER NOT NULL REFERENCES rings(ring_id),
                timestamp TEXT NOT NULL,
                comment TEXT
            )
        """)
        
        // Heart rates (compatible with colmi_r02_client)
        execute("""
            CREATE TABLE IF NOT EXISTS heart_rates (
                heart_rate_id INTEGER PRIMARY KEY AUTOINCREMENT,
                reading INTEGER NOT NULL,
                timestamp TEXT NOT NULL,
                ring_id INTEGER NOT NULL REFERENCES rings(ring_id),
                sync_id INTEGER NOT NULL REFERENCES syncs(sync_id),
                UNIQUE(ring_id, timestamp)
            )
        """)
        
        // Sport details/activity (compatible with colmi_r02_client)
        execute("""
            CREATE TABLE IF NOT EXISTS sport_details (
                sport_detail_id INTEGER PRIMARY KEY AUTOINCREMENT,
                calories INTEGER NOT NULL,
                steps INTEGER NOT NULL,
                distance INTEGER NOT NULL,
                timestamp TEXT NOT NULL,
                ring_id INTEGER NOT NULL REFERENCES rings(ring_id),
                sync_id INTEGER NOT NULL REFERENCES syncs(sync_id),
                UNIQUE(ring_id, timestamp)
            )
        """)
        
        // SpO2 readings (extension)
        execute("""
            CREATE TABLE IF NOT EXISTS spo2_readings (
                spo2_id INTEGER PRIMARY KEY AUTOINCREMENT,
                reading INTEGER NOT NULL,
                timestamp TEXT NOT NULL,
                ring_id INTEGER NOT NULL REFERENCES rings(ring_id),
                sync_id INTEGER NOT NULL REFERENCES syncs(sync_id),
                UNIQUE(ring_id, timestamp)
            )
        """)
        
        // Stress readings (extension)
        execute("""
            CREATE TABLE IF NOT EXISTS stress_readings (
                stress_id INTEGER PRIMARY KEY AUTOINCREMENT,
                reading INTEGER NOT NULL,
                timestamp TEXT NOT NULL,
                ring_id INTEGER NOT NULL REFERENCES rings(ring_id),
                sync_id INTEGER NOT NULL REFERENCES syncs(sync_id),
                UNIQUE(ring_id, timestamp)
            )
        """)
        
        // HRV readings (extension)
        execute("""
            CREATE TABLE IF NOT EXISTS hrv_readings (
                hrv_id INTEGER PRIMARY KEY AUTOINCREMENT,
                hrv_value INTEGER NOT NULL,
                fatigue INTEGER,
                timestamp TEXT NOT NULL,
                ring_id INTEGER NOT NULL REFERENCES rings(ring_id),
                sync_id INTEGER NOT NULL REFERENCES syncs(sync_id),
                UNIQUE(ring_id, timestamp)
            )
        """)
        
        // Sleep sessions (inferred from HR/activity gaps)
        execute("""
            CREATE TABLE IF NOT EXISTS sleep_sessions (
                sleep_id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                duration_minutes INTEGER NOT NULL,
                avg_hr INTEGER,
                min_hr INTEGER,
                quality TEXT,
                ring_id INTEGER NOT NULL REFERENCES rings(ring_id),
                sync_id INTEGER NOT NULL REFERENCES syncs(sync_id),
                UNIQUE(ring_id, start_time)
            )
        """)
        
        // Create indexes
        execute("CREATE INDEX IF NOT EXISTS idx_hr_timestamp ON heart_rates(timestamp)")
        execute("CREATE INDEX IF NOT EXISTS idx_sport_timestamp ON sport_details(timestamp)")
        execute("CREATE INDEX IF NOT EXISTS idx_spo2_timestamp ON spo2_readings(timestamp)")
        execute("CREATE INDEX IF NOT EXISTS idx_sleep_start ON sleep_sessions(start_time)")
        
        // Mark version
        execute("INSERT INTO schema_version (version) VALUES (1)")
        
        logger.info("Schema migration v1 complete")
    }
    
    // MARK: - Ring Management
    
    func getOrCreateRing(address: String) -> Int64 {
        if let cached = ringId { return cached }
        
        // Try to find existing
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT ring_id FROM rings WHERE address = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, address, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                sqlite3_finalize(stmt)
                ringId = id
                return id
            }
        }
        sqlite3_finalize(stmt)
        
        // Create new
        execute("INSERT INTO rings (address) VALUES (?)", [address])
        let id = sqlite3_last_insert_rowid(db)
        ringId = id
        logger.info("Created ring record for \(address)")
        return id
    }
    
    // MARK: - Sync Sessions
    
    func beginSync(ringAddress: String, comment: String? = nil) -> Int64 {
        let ringId = getOrCreateRing(address: ringAddress)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        if let comment = comment {
            execute("INSERT INTO syncs (ring_id, timestamp, comment) VALUES (?, ?, ?)",
                    [ringId, timestamp, comment])
        } else {
            execute("INSERT INTO syncs (ring_id, timestamp) VALUES (?, ?)",
                    [ringId, timestamp])
        }
        
        let syncId = sqlite3_last_insert_rowid(db)
        currentSyncId = syncId
        logger.info("Started sync session \(syncId)")
        return syncId
    }
    
    // MARK: - Heart Rate
    
    func saveHeartRateLog(_ log: HeartRateLog, ringAddress: String) throws {
        let ringId = getOrCreateRing(address: ringAddress)
        let syncId = currentSyncId ?? beginSync(ringAddress: ringAddress)
        
        let formatter = ISO8601DateFormatter()
        var inserted = 0
        
        // Only save valid readings (non-zero)
        for (bpm, time) in log.validReadings {
            let ts = formatter.string(from: time)
            
            // Insert or ignore (unique constraint on ring_id, timestamp)
            execute("""
                INSERT OR IGNORE INTO heart_rates (reading, timestamp, ring_id, sync_id)
                VALUES (?, ?, ?, ?)
            """, [bpm, ts, ringId, syncId])
            
            if sqlite3_changes(db) > 0 { inserted += 1 }
        }
        
        logger.info("Saved \(inserted) heart rate readings for \(log.date)")
    }
    
    func loadHeartRates(from: Date, to: Date) throws -> [(timestamp: Date, reading: Int)] {
        let formatter = ISO8601DateFormatter()
        let fromStr = formatter.string(from: from)
        let toStr = formatter.string(from: to)
        
        var results: [(Date, Int)] = []
        var stmt: OpaquePointer?
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        let sql = "SELECT timestamp, reading FROM heart_rates WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            fromStr.withCString { fromCStr in
                toStr.withCString { toCStr in
                    sqlite3_bind_text(stmt, 1, fromCStr, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, toCStr, -1, SQLITE_TRANSIENT)
                    
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let tsPtr = sqlite3_column_text(stmt, 0) {
                            let ts = String(cString: tsPtr)
                            let reading = Int(sqlite3_column_int(stmt, 1))
                            if let date = formatter.date(from: ts) {
                                results.append((date, reading))
                            }
                        }
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return results
    }
    
    // MARK: - Activity/Steps
    
    func saveActivity(_ activity: DailyActivity, ringAddress: String) throws {
        let ringId = getOrCreateRing(address: ringAddress)
        let syncId = currentSyncId ?? beginSync(ringAddress: ringAddress)
        
        let formatter = ISO8601DateFormatter()
        var inserted = 0
        
        for detail in activity.details {
            let ts = formatter.string(from: detail.timestamp)
            
            // Upsert: update if exists, insert if not
            execute("""
                INSERT INTO sport_details (calories, steps, distance, timestamp, ring_id, sync_id)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(ring_id, timestamp) DO UPDATE SET
                    calories = excluded.calories,
                    steps = excluded.steps,
                    distance = excluded.distance,
                    sync_id = excluded.sync_id
            """, [detail.calories, detail.steps, detail.distance, ts, ringId, syncId])
            
            inserted += 1
        }
        
        logger.info("Saved \(inserted) activity records for \(activity.date)")
    }
    
    func loadActivity(from: Date, to: Date) throws -> [SportDetail] {
        let formatter = ISO8601DateFormatter()
        let fromStr = formatter.string(from: from)
        let toStr = formatter.string(from: to)
        
        var results: [SportDetail] = []
        var stmt: OpaquePointer?
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        let sql = """
            SELECT timestamp, steps, calories, distance FROM sport_details 
            WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            fromStr.withCString { fromCStr in
                toStr.withCString { toCStr in
                    sqlite3_bind_text(stmt, 1, fromCStr, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, toCStr, -1, SQLITE_TRANSIENT)
                    
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let tsPtr = sqlite3_column_text(stmt, 0) {
                            let ts = String(cString: tsPtr)
                            if let date = formatter.date(from: ts) {
                                results.append(SportDetail(
                                    timestamp: date,
                                    steps: Int(sqlite3_column_int(stmt, 1)),
                                    calories: Int(sqlite3_column_int(stmt, 2)),
                                    distance: Int(sqlite3_column_int(stmt, 3))
                                ))
                            }
                        }
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return results
    }
    
    // MARK: - SpO2
    
    func saveSpO2Log(_ log: SpO2Log, ringAddress: String) throws {
        let ringId = getOrCreateRing(address: ringAddress)
        let syncId = currentSyncId ?? beginSync(ringAddress: ringAddress)
        
        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: log.date)
        var inserted = 0
        
        // SpO2 readings are at 5-minute intervals like HR
        for (index, value) in log.readings.enumerated() {
            guard value > 0 && value <= 100 else { continue }
            
            let time = calendar.date(byAdding: .minute, value: index * 5, to: startOfDay)!
            let ts = formatter.string(from: time)
            
            execute("""
                INSERT OR IGNORE INTO spo2_readings (reading, timestamp, ring_id, sync_id)
                VALUES (?, ?, ?, ?)
            """, [value, ts, ringId, syncId])
            
            if sqlite3_changes(db) > 0 { inserted += 1 }
        }
        
        logger.info("Saved \(inserted) SpO2 readings")
    }
    
    // MARK: - Sleep
    
    func saveSleepSession(_ session: CPSleepSession, ringAddress: String, avgHR: Int? = nil, minHR: Int? = nil) throws {
        let ringId = getOrCreateRing(address: ringAddress)
        let syncId = currentSyncId ?? beginSync(ringAddress: ringAddress)
        
        let formatter = ISO8601DateFormatter()
        let startTs = formatter.string(from: session.startTime)
        let endTs = formatter.string(from: session.endTime)
        
        // Quality category based on score
        let quality: String
        let score = session.qualityScore
        if score >= 80 {
            quality = "excellent"
        } else if score >= 60 {
            quality = "good"
        } else if score >= 40 {
            quality = "fair"
        } else {
            quality = "poor"
        }
        
        execute("""
            INSERT OR REPLACE INTO sleep_sessions 
            (start_time, end_time, duration_minutes, avg_hr, min_hr, quality, ring_id, sync_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            startTs, endTs, session.durationMinutes,
            avgHR as Any, minHR as Any, quality,
            ringId, syncId
        ])
        
        logger.info("Saved sleep session: \(session.durationMinutes) minutes, quality: \(quality)")
    }
    
    // MARK: - Statistics
    
    func getStats() -> (heartRates: Int, activities: Int, spo2: Int, sleepSessions: Int) {
        var hr = 0, act = 0, spo2 = 0, sleep = 0
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM heart_rates", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                hr = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sport_details", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                act = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM spo2_readings", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                spo2 = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sleep_sessions", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                sleep = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        return (hr, act, spo2, sleep)
    }
    
    // MARK: - Helpers
    
    private func execute(_ sql: String, _ params: [Any] = []) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare: \(sql) - \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        // Bind parameters
        // Use SQLITE_TRANSIENT to have SQLite copy string data
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case let i as Int:
                sqlite3_bind_int64(stmt, idx, Int64(i))
            case let i as Int64:
                sqlite3_bind_int64(stmt, idx, i)
            case let s as String:
                sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case is NSNull:
                sqlite3_bind_null(stmt, idx)
            case let opt as Optional<Any>:
                if case .none = opt {
                    sqlite3_bind_null(stmt, idx)
                }
            default:
                if let s = param as? String {
                    sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, idx)
                }
            }
        }
        
        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE && result != SQLITE_ROW {
            // Ignore constraint violations (expected for INSERT OR IGNORE)
            let errCode = sqlite3_errcode(db)
            if errCode != SQLITE_CONSTRAINT {
                logger.error("Execute failed: \(String(cString: sqlite3_errmsg(self.db)))")
            }
        }
    }
}

// MARK: - Errors

enum SQLiteError: Error {
    case openFailed(String)
    case queryFailed(String)
}
