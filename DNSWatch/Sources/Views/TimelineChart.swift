import Charts
import SwiftUI

struct TimelineChart: View {
    let data: [TimelineBucket]
    let showEncryptedDNSHint: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if self.data.isEmpty || self.data.allSatisfy({ $0.queryCount == 0 }) {
                self.emptyState
            } else {
                VStack(spacing: 12) {
                    // Summary stats
                    HStack(spacing: 20) {
                        TimelineStat(
                            title: "Peak",
                            value: "\(self.maxQueryCount)",
                            subtitle: "queries/min"
                        )
                        TimelineStat(
                            title: "Average",
                            value: String(format: "%.1f", self.averageQueries),
                            subtitle: "queries/min"
                        )
                        TimelineStat(
                            title: "Total",
                            value: "\(self.totalQueries)",
                            subtitle: "last hour"
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Sparkline chart
                    Chart(self.data) { bucket in
                        AreaMark(
                            x: .value("Time", bucket.midpoint),
                            y: .value("Queries", bucket.queryCount)
                        )
                        .foregroundStyle(self.areaGradient)
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Time", bucket.midpoint),
                            y: .value("Queries", bucket.queryCount)
                        )
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisValueLabel(format: .dateTime.hour().minute())
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.gray.opacity(0.3))
                            AxisValueLabel()
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .chartYScale(domain: 0 ... (self.maxQueryCount + max(5, self.maxQueryCount / 4)))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(self.showEncryptedDNSHint ? "No UDP/53 traffic" : "No DNS queries yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(self.showEncryptedDNSHint
                 ? "Encrypted DNS (DoH/DoT) is hidden from capture"
                 : "Activity timeline will appear here")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.4),
                Color.blue.opacity(0.1),
                Color.blue.opacity(0.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var maxQueryCount: Int {
        self.data.map(\.queryCount).max() ?? 0
    }

    private var averageQueries: Double {
        guard !self.data.isEmpty else { return 0 }
        let nonZero = self.data.filter { $0.queryCount > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return Double(nonZero.map(\.queryCount).reduce(0, +)) / Double(nonZero.count)
    }

    private var totalQueries: Int {
        self.data.map(\.queryCount).reduce(0, +)
    }
}

// MARK: - Timeline Stat

struct TimelineStat: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(self.title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text(self.value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(self.subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
