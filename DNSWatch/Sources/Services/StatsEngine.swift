import Combine
import Foundation

/// Aggregates and manages DNS query statistics
@MainActor
final class StatsEngine: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var totalQueries: Int = 0
    @Published private(set) var queriesLastMinute: Int = 0
    @Published private(set) var uniqueDomains: Int = 0
    @Published private(set) var topDomains: [DomainStat] = []
    @Published private(set) var queryTypeStats: [QueryTypeStat] = []
    @Published private(set) var timelineData: [TimelineBucket] = []
    @Published private(set) var recentQueries: [DNSQuery] = []

    // MARK: - Private Properties

    private var allQueries: [DNSQuery] = []
    private var domainCounts: [String: Int] = [:]
    private var queryTypeCounts: [DNSQueryType: Int] = [:]
    private var timelineBuckets: [Date: Int] = [:]

    private let bucketInterval: TimeInterval = 60 // 1 minute buckets
    private let maxRecentQueries = 100
    private let maxTimelineMinutes = 60 // Keep last hour for display

    private var updateTimer: Timer?
    private var saveTimer: Timer?
    private let persistence = Persistence.shared

    // MARK: - Initialization

    init() {
        // Load persisted config
        self.persistence.loadConfig()

        // Load persisted data
        self.loadPersistedData()

        // Start periodic updates
        self.startPeriodicUpdates()
        self.startAutoSave()
    }

    deinit {
        // Save on deinit (though MainActor makes this tricky)
        updateTimer?.invalidate()
        saveTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Record a new DNS query
    func recordQuery(_ query: DNSQuery) {
        self.allQueries.append(query)
        self.totalQueries += 1

        // Update domain counts
        let domain = query.baseDomain
        self.domainCounts[domain, default: 0] += 1

        // Update query type counts
        self.queryTypeCounts[query.queryType, default: 0] += 1

        // Update timeline
        let bucketTime = self.bucketStartTime(for: query.timestamp)
        self.timelineBuckets[bucketTime, default: 0] += 1

        // Update recent queries list
        self.recentQueries.insert(query, at: 0)
        if self.recentQueries.count > self.maxRecentQueries {
            self.recentQueries.removeLast()
        }

        // Recalculate derived stats
        self.updateDerivedStats()
    }

    /// Reset all statistics
    func reset() {
        self.allQueries.removeAll()
        self.domainCounts.removeAll()
        self.queryTypeCounts.removeAll()
        self.timelineBuckets.removeAll()
        self.recentQueries.removeAll()

        self.totalQueries = 0
        self.queriesLastMinute = 0
        self.uniqueDomains = 0
        self.topDomains = []
        self.queryTypeStats = []
        self.timelineData = []

        // Clear persisted data
        self.persistence.clear()
    }

    /// Force save to disk
    func save() {
        self.persistence.save(queries: self.allQueries)
    }

    /// Get data TTL in hours
    var dataTTLHours: Int {
        Int(self.persistence.config.dataTTL / 3600)
    }

    /// Set data TTL in hours
    func setDataTTL(hours: Int) {
        self.persistence.config.dataTTL = TimeInterval(hours) * 3600
        self.persistence.saveConfig()
    }

    // MARK: - Private Methods

    private func loadPersistedData() {
        let queries = self.persistence.load()

        guard !queries.isEmpty else { return }

        // Rebuild state from persisted queries
        for query in queries {
            self.allQueries.append(query)
            self.totalQueries += 1

            let domain = query.baseDomain
            self.domainCounts[domain, default: 0] += 1
            self.queryTypeCounts[query.queryType, default: 0] += 1

            let bucketTime = self.bucketStartTime(for: query.timestamp)
            self.timelineBuckets[bucketTime, default: 0] += 1
        }

        // Update recent queries (most recent first)
        self.recentQueries = Array(queries.sorted { $0.timestamp > $1.timestamp }.prefix(self.maxRecentQueries))

        // Update derived stats
        self.updateDerivedStats()
        self.updateRateStats()
    }

    private func startPeriodicUpdates() {
        self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRateStats()
                self?.pruneOldData()
            }
        }
    }

    private func startAutoSave() {
        self.saveTimer = Timer
            .scheduledTimer(withTimeInterval: self.persistence.config.saveInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.save()
                }
            }
    }

    private func updateDerivedStats() {
        // Update unique domains count
        self.uniqueDomains = self.domainCounts.count

        // Update top domains (top 20)
        let sortedDomains = self.domainCounts.sorted { $0.value > $1.value }
        let totalForPercentage = max(totalQueries, 1)
        self.topDomains = sortedDomains.prefix(20).map { domain, count in
            DomainStat(
                domain: domain,
                count: count,
                percentage: Double(count) / Double(totalForPercentage) * 100
            )
        }

        // Update query type stats
        let sortedTypes = self.queryTypeCounts.sorted { $0.value > $1.value }
        self.queryTypeStats = sortedTypes.map { type, count in
            QueryTypeStat(
                queryType: type,
                count: count,
                percentage: Double(count) / Double(totalForPercentage) * 100
            )
        }

        // Update timeline data
        self.updateTimelineData()
    }

    private func updateRateStats() {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        self.queriesLastMinute = self.allQueries.count(where: { $0.timestamp > oneMinuteAgo })
    }

    private func updateTimelineData() {
        let now = Date()
        let startTime = now.addingTimeInterval(-TimeInterval(self.maxTimelineMinutes * 60))

        var buckets: [TimelineBucket] = []
        var currentBucketStart = self.bucketStartTime(for: startTime)

        while currentBucketStart <= now {
            let bucketEnd = currentBucketStart.addingTimeInterval(self.bucketInterval)
            let count = self.timelineBuckets[currentBucketStart] ?? 0

            buckets.append(TimelineBucket(
                startTime: currentBucketStart,
                endTime: bucketEnd,
                queryCount: count
            ))

            currentBucketStart = bucketEnd
        }

        self.timelineData = buckets
    }

    private func pruneOldData() {
        // Prune based on TTL for persistence, but keep timeline display window
        let displayCutoff = Date().addingTimeInterval(-TimeInterval(self.maxTimelineMinutes * 60))

        // Remove old timeline buckets (for display)
        self.timelineBuckets = self.timelineBuckets.filter { $0.key >= displayCutoff }

        // Prune queries older than TTL (for storage efficiency)
        let ttlCutoff = Date().addingTimeInterval(-self.persistence.config.dataTTL)
        let beforeCount = self.allQueries.count
        self.allQueries.removeAll { $0.timestamp < ttlCutoff }

        if beforeCount != self.allQueries.count {
            // Rebuild counts if we removed queries
            self.rebuildCounts()
        }
    }

    private func rebuildCounts() {
        self.domainCounts.removeAll()
        self.queryTypeCounts.removeAll()
        self.totalQueries = 0

        for query in self.allQueries {
            self.totalQueries += 1
            let domain = query.baseDomain
            self.domainCounts[domain, default: 0] += 1
            self.queryTypeCounts[query.queryType, default: 0] += 1
        }

        self.updateDerivedStats()
    }

    private func bucketStartTime(for date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        let bucketSeconds = floor(seconds / self.bucketInterval) * self.bucketInterval
        return Date(timeIntervalSince1970: bucketSeconds)
    }
}
