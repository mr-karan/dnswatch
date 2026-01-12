import Foundation

/// Represents a single DNS query captured from the network
struct DNSQuery: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let domain: String
    let queryType: DNSQueryType
    let isResponse: Bool
    let responseCode: DNSResponseCode?
    let transactionId: UInt16

    init(
        timestamp: Date = Date(),
        domain: String,
        queryType: DNSQueryType,
        isResponse: Bool = false,
        responseCode: DNSResponseCode? = nil,
        transactionId: UInt16 = 0
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.domain = domain
        self.queryType = queryType
        self.isResponse = isResponse
        self.responseCode = responseCode
        self.transactionId = transactionId
    }

    /// Returns the base domain (e.g., "apple.com" from "www.apple.com")
    var baseDomain: String {
        let parts = self.domain.split(separator: ".")
        guard parts.count >= 2 else { return self.domain }
        return parts.suffix(2).joined(separator: ".")
    }
}

/// Time bucket for timeline aggregation
struct TimelineBucket: Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    var queryCount: Int

    init(startTime: Date, endTime: Date, queryCount: Int = 0) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.queryCount = queryCount
    }

    var midpoint: Date {
        Date(timeIntervalSince1970: (self.startTime.timeIntervalSince1970 + self.endTime.timeIntervalSince1970) / 2)
    }
}

/// Domain statistics for display
struct DomainStat: Identifiable {
    let id = UUID()
    let domain: String
    let count: Int
    let percentage: Double
}

/// Query type statistics for display
struct QueryTypeStat: Identifiable {
    let id = UUID()
    let queryType: DNSQueryType
    let count: Int
    let percentage: Double
}
