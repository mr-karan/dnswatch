<p align="center">
  <img src="docs/logo.svg" alt="DNSWatch" width="128" height="128">
</p>

# DNSWatch

[![macOS 14+](https://img.shields.io/badge/macOS-14.0+-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

A privacy-friendly macOS menu bar app that monitors and visualizes DNS queries in real-time. All data stays on your device.

<p align="center">
  <img src="docs/screenshot.png" alt="DNSWatch Screenshot" width="400">
</p>

## Features

- **Real-time DNS capture** using libpcap
- **Smart interface detection** (supports Tailscale/VPN)
- **Beautiful charts** — top domains, query types, timeline
- **Persistent history** with configurable retention (1–90 days)
- **Privacy-first** — all data stays local

## Installation

### Build from Source

```bash
git clone https://github.com/mr-karan/dnswatch.git
cd dnswatch
make build
```

### Download

Grab the latest from [GitHub Releases](https://github.com/mr-karan/dnswatch/releases).

### macOS Security Warning

Since the app isn't signed with an Apple Developer ID, macOS will show a warning. To open:

1. **Right-click** the app → **Open** → **Open** (in the dialog)

Or remove the quarantine flag:
```bash
xattr -cr /Applications/DNSWatch.app
```

## Setup

DNSWatch needs BPF permissions to capture packets:

```bash
# Grant permissions (resets on reboot)
sudo chmod o+r /dev/bpf*

# Or run with sudo
sudo .build/DNSWatch.app/Contents/MacOS/DNSWatch
```

Then click the network icon in your menu bar.

## How It Works

```
App DNS Query → Network Interface → BPF (/dev/bpf*)
                                           ↓
                                ┌────────────────────┐
                                │      DNSWatch      │
                                │  libpcap capture   │
                                │  DNS parser        │
                                │  Stats engine      │
                                │  SwiftUI charts    │
                                └────────────────────┘
```

Uses [libpcap](https://www.tcpdump.org/) to capture UDP port 53 traffic, parses DNS protocol to extract domains and query types, aggregates statistics, and displays via Swift Charts.

## Development

```bash
./Scripts/compile_and_run.sh    # Dev loop
make build                       # Release build
./Scripts/package_app.sh --sign  # Package DMG
```

See [AGENTS.md](AGENTS.md) for architecture details.

## Privacy

All data stays on your device in `~/Library/Application Support/DNSWatch/`. Nothing is sent anywhere.

## License

MIT
