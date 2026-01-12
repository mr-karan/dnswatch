# AGENTS.md

Guidelines for AI agents (Claude, Copilot, Cursor, etc.) working on DNSWatch.

## Project Overview

DNSWatch is a macOS menu bar app that captures and visualizes DNS queries using libpcap. Built with Swift 6 and SwiftUI, targeting macOS 14+.

## Build Commands

```bash
make build        # Build the app to .build/DNSWatch.app
make run          # Build and run (requires BPF permissions)
make run-sudo     # Build and run with sudo
make clean        # Remove build artifacts

# Development loop (kill, rebuild, run)
./Scripts/compile_and_run.sh

# Package for release
./Scripts/package_app.sh --sign
```

**BPF permissions required** for packet capture:
```bash
sudo chmod o+r /dev/bpf*
```

**Kill running instance**:
```bash
pkill -f DNSWatch
```

## Architecture

### Data Flow

```
Network Interface (en0, utun*, lo0)
         ↓
PacketCapture (libpcap, BPF filter "udp port 53")
         ↓
DNSParser (extracts domain, query type from UDP payload)
         ↓
StatsEngine (@MainActor, aggregates, publishes via @Published)
         ↓
SwiftUI Views (Charts: bar, donut, sparkline)
```

### File Structure

```
DNSWatch/Sources/
├── DNSWatchApp.swift           # @main entry point
├── AppDelegate.swift         # NSStatusItem, NSPopover, capture orchestration
├── Models/
│   └── DNSQuery.swift        # Query data model, stats structs
├── Services/
│   ├── PacketCapture.swift   # libpcap wrapper (@_silgen_name bindings)
│   ├── DNSParser.swift       # DNS protocol parser (handles compression)
│   ├── StatsEngine.swift     # @MainActor stats aggregation
│   ├── InterfaceDetector.swift # Network interface auto-detection
│   └── Persistence.swift     # JSON file storage for stats
├── Views/
│   ├── ContentView.swift     # Main popover + settings
│   ├── TopDomainsChart.swift # Horizontal bar chart
│   ├── QueryTypesChart.swift # Donut chart (SectorMark)
│   └── TimelineChart.swift   # Sparkline area chart
└── Utilities/
    └── DNSTypes.swift        # DNS query type enums
```

## Key Patterns

### Actor Isolation (Swift 6)

StatsEngine and AppDelegate are both `@MainActor`:

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate { ... }

@MainActor
final class StatsEngine: ObservableObject { ... }
```

### libpcap Integration

Uses `@_silgen_name` to bind C functions without a bridging header:

```swift
@_silgen_name("pcap_open_live")
private func pcap_open_live(...) -> OpaquePointer?
```

### Interface Detection

Auto-detects interfaces in priority order:
1. Route to DNS server (special-cases Tailscale 100.100.x.x)
2. Default route interface
3. Common interfaces (en0, en1, lo0)

Captures on up to 3 interfaces simultaneously.

**Note**: The "any" pseudo-interface doesn't work on macOS due to SIP.

### DNS Parsing Safety

Protections against malformed packets:
- Tracks visited offsets to detect compression pointer cycles
- Limits iterations to prevent infinite loops
- Validates IPv4 header length (IHL >= 5)
- Rejects reserved/extended label types

## Technical Notes

- **macOS 14.0+ required** for SectorMark (donut charts)
- **No sandbox** — libpcap requires BPF device access
- **Links against system libpcap** (`-lpcap`)
- Stats persisted to `~/Library/Application Support/DNSWatch/`

## Code Style

- **Indentation**: 4 spaces
- **Line length**: ~100 chars soft limit
- **MARK comments**: Use `// MARK: - Section`
- **Access control**: Prefer `private` by default

## Common Tasks

### Adding a new DNS query type

1. Add case to `DNSQueryType` enum in `DNSTypes.swift`
2. Update `init(rawValue:)` switch
3. Add `displayName` and `description`

### Adding a new chart

1. Create `NewChart.swift` in `Views/`
2. Add tab in `ContentView.swift` picker
3. Add case in chart switch statement

## Files to Never Edit

- `.build/` — Generated build artifacts
- `dist/` — Generated distribution files

## Debugging

- Run from terminal to see `print()` output
- Check `~/Library/Application Support/DNSWatch/stats.json` for persisted data
- If no queries appear, verify BPF permissions: `ls -la /dev/bpf0`
