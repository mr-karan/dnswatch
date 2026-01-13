import Charts
import SwiftUI

struct QueryTypesChart: View {
    let stats: [QueryTypeStat]
    let showEncryptedDNSHint: Bool

    private let colors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .yellow, .red, .mint, .indigo,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if self.stats.isEmpty {
                self.emptyState
            } else {
                VStack(spacing: 16) {
                    // Donut chart
                    Chart(self.stats) { stat in
                        SectorMark(
                            angle: .value("Count", stat.count),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Type", stat.queryType.displayName))
                        .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(domain: self.stats.map(\.queryType.displayName), range: self.colors)
                    .frame(height: 140)
                    .padding(.horizontal, 40)

                    // Legend as list
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(self.stats.enumerated()), id: \.element.id) { index, stat in
                                QueryTypeRow(
                                    color: self.colors[index % self.colors.count],
                                    type: stat.queryType.displayName,
                                    description: stat.queryType.description,
                                    count: stat.count,
                                    percentage: stat.percentage
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(self.showEncryptedDNSHint ? "No UDP/53 traffic" : "No DNS queries yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(self.showEncryptedDNSHint
                 ? "Encrypted DNS (DoH/DoT) is hidden from capture"
                 : "Query type distribution will appear here")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Query Type Row

struct QueryTypeRow: View {
    let color: Color
    let type: String
    let description: String
    let count: Int
    let percentage: Double

    var body: some View {
        HStack(spacing: 10) {
            // Color indicator
            Circle()
                .fill(self.color)
                .frame(width: 8, height: 8)

            // Type name
            Text(self.type)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 50, alignment: .leading)

            // Description
            Text(self.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Count & percentage
            HStack(spacing: 6) {
                Text("\(self.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

                Text(String(format: "%.0f%%", self.percentage))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}
