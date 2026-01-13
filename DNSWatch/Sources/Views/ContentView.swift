import Charts
import SwiftUI

struct ContentView: View {
    @ObservedObject var statsEngine: StatsEngine
    let onReset: () -> Void
    let onToggleCapture: () -> Void
    let isCapturing: () -> Bool
    let onQuit: () -> Void
    let activeInterfaces: () -> [String]
    let onInstallBPFHelper: () -> Void
    let onUninstallBPFHelper: () -> Void

    @State private var selectedTab = 0
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if self.showSettings {
                self.settingsView
            } else {
                self.mainView
            }
        }
        .frame(width: 380, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Main View

    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            self.headerSection
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Stats cards
            self.statsCards
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Tab selector
            Picker("", selection: self.$selectedTab) {
                Text("Domains").tag(0)
                Text("Types").tag(1)
                Text("Timeline").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Chart content
            Group {
                switch self.selectedTab {
                case 0:
                    TopDomainsChart(domains: self.statsEngine.topDomains)
                case 1:
                    QueryTypesChart(stats: self.statsEngine.queryTypeStats)
                case 2:
                    TimelineChart(data: self.statsEngine.timelineData)
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
                .padding(.horizontal, 16)

            // Footer
            self.footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Settings View

    private var settingsView: some View {
        VStack(spacing: 0) {
            // Settings header
            HStack {
                Button(action: { self.showSettings = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                // Invisible spacer for centering
                Text("Back")
                    .font(.system(size: 13))
                    .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Data Retention Section
                    SettingsSection(title: "Data Retention") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Keep DNS query history for:")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(TTLOption.allCases) { option in
                                    TTLButton(
                                        option: option,
                                        isSelected: self.statsEngine.dataTTLHours == option.hours,
                                        action: {
                                            self.statsEngine.setDataTTL(hours: option.hours)
                                        }
                                    )
                                }
                            }

                            Text("Older queries are automatically deleted.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Storage Info Section
                    SettingsSection(title: "Storage") {
                        let info = Persistence.shared.storageInfo()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Queries stored:")
                                Spacer()
                                Text("\(info.queryCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 13))

                            HStack {
                                Text("File size:")
                                Spacer()
                                Text(self.formatBytes(info.size))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 13))

                            HStack {
                                Text("Location:")
                                Spacer()
                                Text("~/Library/Application Support/DNSWatch/")
                                    .foregroundStyle(.tertiary)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .font(.system(size: 13))
                        }
                    }

                    // Capture Permissions Section
                    SettingsSection(title: "Capture Permissions") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Install the helper to restore BPF permissions at boot.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Button("Install Helper") {
                                    self.onInstallBPFHelper()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("Remove Helper") {
                                    self.onUninstallBPFHelper()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text("You may need to log out and back in after installing.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // About Section
                    SettingsSection(title: "About") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Version:")
                                Spacer()
                                Text("1.0.0")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))

                            HStack {
                                Text("Capture:")
                                Spacer()
                                Text(self.isCapturing() ? self.activeInterfaces().joined(separator: ", ") : "Paused")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DNSWatch")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                HStack(spacing: 4) {
                    Circle()
                        .fill(self.isCapturing() ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(self.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button(action: { self.showSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
                Button("Reset Statistics") {
                    self.onReset()
                }
                Divider()
                Button("Quit DNSWatch") {
                    self.onQuit()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28, height: 28)
        }
    }

    private var statusText: String {
        if !self.isCapturing() {
            return "Paused"
        }
        let interfaces = self.activeInterfaces()
        if interfaces.isEmpty {
            return "Starting..."
        }
        return "Capturing on \(interfaces.joined(separator: ", "))"
    }

    // MARK: - Stats Cards

    private var statsCards: some View {
        HStack(spacing: 10) {
            StatCard(
                title: "Total",
                value: self.formatNumber(self.statsEngine.totalQueries),
                icon: "number.circle.fill",
                color: .blue
            )

            StatCard(
                title: "Per Min",
                value: "\(self.statsEngine.queriesLastMinute)",
                icon: "speedometer",
                color: .orange
            )

            StatCard(
                title: "Unique",
                value: self.formatNumber(self.statsEngine.uniqueDomains),
                icon: "globe",
                color: .purple
            )
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: self.onToggleCapture) {
                HStack(spacing: 6) {
                    Image(systemName: self.isCapturing() ? "pause.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(self.isCapturing() ? "Pause" : "Resume")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(self.isCapturing() ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                .foregroundColor(self.isCapturing() ? .orange : .green)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Spacer()

            if self.statsEngine.totalQueries > 0 {
                Text("Last: \(self.statsEngine.recentQueries.first?.domain ?? "—")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        return "\(number)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes >= 1000 {
            return String(format: "%.1f KB", Double(bytes) / 1000)
        }
        return "\(bytes) B"
    }
}

// MARK: - TTL Options

enum TTLOption: CaseIterable, Identifiable {
    case oneDay
    case oneWeek
    case thirtyDays
    case ninetyDays

    var id: Int { self.hours }

    var hours: Int {
        switch self {
        case .oneDay: 24
        case .oneWeek: 24 * 7
        case .thirtyDays: 24 * 30
        case .ninetyDays: 24 * 90
        }
    }

    var label: String {
        switch self {
        case .oneDay: "1 Day"
        case .oneWeek: "1 Week"
        case .thirtyDays: "30 Days"
        case .ninetyDays: "90 Days"
        }
    }
}

// MARK: - Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 12) {
                self.content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct TTLButton: View {
    let option: TTLOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(self.option.label)
                .font(.system(size: 12, weight: self.isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(self.isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(self.isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: self.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(self.color)
                Text(self.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(self.value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(self.color.opacity(0.08))
        .cornerRadius(10)
    }
}
