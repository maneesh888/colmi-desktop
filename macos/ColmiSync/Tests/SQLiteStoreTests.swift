import Testing
import Foundation
@testable import ColmiSync

@Suite("SQLite Store Tests")
struct SQLiteStoreTests {
    
    @Test("Store opens and creates schema")
    func testOpen() async throws {
        // Use temp file
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-\(UUID().uuidString).db")
        
        // Clean up after test
        defer { try? FileManager.default.removeItem(at: dbPath) }
        
        // Open store - should create schema
        let store = try await SQLiteStore.open(path: dbPath)
        
        // Verify file was created
        #expect(FileManager.default.fileExists(atPath: dbPath.path))
        
        // Verify stats return zeros (empty database)
        let stats = await store.getStats()
        #expect(stats.heartRates == 0)
        #expect(stats.activities == 0)
        #expect(stats.spo2 == 0)
        #expect(stats.sleepSessions == 0)
    }
    
    @Test("Ring creation and caching")
    func testRingManagement() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        
        let store = try await SQLiteStore.open(path: dbPath)
        
        // Create ring
        let ringId1 = await store.getOrCreateRing(address: "AA:BB:CC:DD:EE:FF")
        #expect(ringId1 > 0)
        
        // Same address should return same ID (cached)
        let ringId2 = await store.getOrCreateRing(address: "AA:BB:CC:DD:EE:FF")
        #expect(ringId1 == ringId2)
    }
    
    @Test("Heart rate log save and load")
    func testHeartRateStorage() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        
        let store = try await SQLiteStore.open(path: dbPath)
        
        // Create test HR log
        let today = Calendar.current.startOfDay(for: Date())
        var readings = Array(repeating: 0, count: 288)
        readings[0] = 65
        readings[1] = 68
        readings[2] = 70
        let hrLog = HeartRateLog(date: today, readings: readings)
        
        // Save
        try await store.saveHeartRateLog(hrLog, ringAddress: "AA:BB:CC:DD:EE:FF")
        
        // Verify count
        let stats = await store.getStats()
        #expect(stats.heartRates == 3)  // 3 non-zero readings
        
        // Load
        let loaded = try await store.loadHeartRates(
            from: today,
            to: Calendar.current.date(byAdding: .day, value: 1, to: today)!
        )
        #expect(loaded.count == 3)
        #expect(loaded[0].reading == 65)
    }
    
    @Test("Activity storage")
    func testActivityStorage() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        
        let store = try await SQLiteStore.open(path: dbPath)
        
        // Create test activity
        let now = Date()
        let detail = SportDetail(timestamp: now, steps: 1000, calories: 50, distance: 800)
        let activity = DailyActivity(date: now, details: [detail])
        
        // Save
        try await store.saveActivity(activity, ringAddress: "AA:BB:CC:DD:EE:FF")
        
        // Verify
        let stats = await store.getStats()
        #expect(stats.activities == 1)
        
        // Load
        let loaded = try await store.loadActivity(
            from: Calendar.current.date(byAdding: .hour, value: -1, to: now)!,
            to: Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        )
        #expect(loaded.count == 1)
        #expect(loaded[0].steps == 1000)
        #expect(loaded[0].calories == 50)
    }
    
    @Test("Sync session management")
    func testSyncSession() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        
        let store = try await SQLiteStore.open(path: dbPath)
        
        // Begin sync
        let syncId = await store.beginSync(ringAddress: "AA:BB:CC:DD:EE:FF", comment: "Test sync")
        #expect(syncId > 0)
    }
}
