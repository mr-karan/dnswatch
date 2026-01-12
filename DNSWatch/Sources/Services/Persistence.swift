import Foundation

/// Handles persistence of DNS stats to disk
final class Persistence {
    // MARK: - Configuration

    struct Config {
        /// How long to keep query data (default: 30 days)
        var dataTTL: TimeInterval = 30 * 24 * 60 * 60

        /// How often to auto-save (default: 30 seconds)
        var saveInterval: TimeInterval = 30

        /// Maximum queries to persist (to limit file size)
        var maxQueries: Int = 10000
    }

    static let shared = Persistence()
    var config = Config()

    // MARK: - Storage Paths

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("DNSWatch", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("stats.json")
    }

    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("DNSWatch", isDirectory: true)
        return appDir.appendingPathComponent("config.json")
    }

    // MARK: - Data Structures

    struct PersistedStats: Codable {
        var queries: [PersistedQuery]
        var savedAt: Date

        struct PersistedQuery: Codable {
            let timestamp: Date
            let domain: String
            let queryType: UInt16
            let isResponse: Bool
        }
    }

    struct PersistedConfig: Codable {
        var dataTTLHours: Int
        var maxQueries: Int
    }

    // MARK: - Public Methods

    /// Save stats to disk
    func save(queries: [DNSQuery]) {
        let cutoff = Date().addingTimeInterval(-self.config.dataTTL)

        // Filter to TTL and limit count
        let recentQueries = queries
            .filter { $0.timestamp > cutoff }
            .suffix(self.config.maxQueries)

        let persisted = PersistedStats(
            queries: recentQueries.map { query in
                PersistedStats.PersistedQuery(
                    timestamp: query.timestamp,
                    domain: query.domain,
                    queryType: query.queryType.rawValue,
                    isResponse: query.isResponse
                )
            },
            savedAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: self.storageURL, options: .atomic)
            print("💾 Saved \(persisted.queries.count) queries to disk")
        } catch {
            print("❌ Failed to save stats: \(error)")
        }
    }

    /// Load stats from disk
    func load() -> [DNSQuery] {
        guard FileManager.default.fileExists(atPath: self.storageURL.path) else {
            print("📂 No persisted stats found")
            return []
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let persisted = try JSONDecoder().decode(PersistedStats.self, from: data)

            let cutoff = Date().addingTimeInterval(-self.config.dataTTL)

            // Filter expired queries
            let validQueries = persisted.queries
                .filter { $0.timestamp > cutoff }
                .map { pq in
                    DNSQuery(
                        timestamp: pq.timestamp,
                        domain: pq.domain,
                        queryType: DNSQueryType(rawValue: pq.queryType),
                        isResponse: pq.isResponse
                    )
                }

            print("📂 Loaded \(validQueries.count) queries from disk (saved \(self.formatAge(persisted.savedAt)) ago)")
            return validQueries
        } catch {
            print("❌ Failed to load stats: \(error)")
            return []
        }
    }

    /// Save configuration
    func saveConfig() {
        let persistedConfig = PersistedConfig(
            dataTTLHours: Int(config.dataTTL / 3600),
            maxQueries: self.config.maxQueries
        )

        do {
            let data = try JSONEncoder().encode(persistedConfig)
            try data.write(to: self.configURL, options: .atomic)
        } catch {
            print("❌ Failed to save config: \(error)")
        }
    }

    /// Load configuration
    func loadConfig() {
        guard FileManager.default.fileExists(atPath: self.configURL.path) else { return }

        do {
            let data = try Data(contentsOf: configURL)
            let persistedConfig = try JSONDecoder().decode(PersistedConfig.self, from: data)

            self.config.dataTTL = TimeInterval(persistedConfig.dataTTLHours) * 3600
            self.config.maxQueries = persistedConfig.maxQueries
        } catch {
            print("❌ Failed to load config: \(error)")
        }
    }

    /// Clear all persisted data
    func clear() {
        try? FileManager.default.removeItem(at: self.storageURL)
        print("🗑️ Cleared persisted stats")
    }

    /// Get storage info
    func storageInfo() -> (path: String, size: Int64, queryCount: Int) {
        let path = self.storageURL.path
        var size: Int64 = 0
        var count = 0

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
            size = attrs[.size] as? Int64 ?? 0
        }

        if let data = try? Data(contentsOf: storageURL),
           let persisted = try? JSONDecoder().decode(PersistedStats.self, from: data)
        {
            count = persisted.queries.count
        }

        return (path, size, count)
    }

    // MARK: - Helpers

    private func formatAge(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
}
