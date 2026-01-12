import Charts
import SwiftUI

struct TopDomainsChart: View {
    let domains: [DomainStat]

    private let maxDomainsToShow = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if self.domains.isEmpty {
                self.emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(self.domains.prefix(self.maxDomainsToShow).enumerated()),
                                id: \.element.id)
                        { index, domain in
                            DomainRow(
                                rank: index + 1,
                                domain: domain.domain,
                                count: domain.count,
                                percentage: domain.percentage,
                                maxCount: self.domains.first?.count ?? 1
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No DNS queries yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Queries will appear as they're captured")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Domain Row

struct DomainRow: View {
    let rank: Int
    let domain: String
    let count: Int
    let percentage: Double
    let maxCount: Int

    var body: some View {
        HStack(spacing: 10) {
            // Rank badge
            Text("\(self.rank)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            // Domain name
            Text(self.domain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Bar + count
            HStack(spacing: 8) {
                // Mini bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.15))

                        // Fill
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * self.barWidthRatio)
                    }
                }
                .frame(width: 60, height: 14)

                // Count
                Text("\(self.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var barWidthRatio: CGFloat {
        guard self.maxCount > 0 else { return 0 }
        return CGFloat(self.count) / CGFloat(self.maxCount)
    }
}
