# icloud-status

[![GitHub release](https://img.shields.io/github/v/tag/aladac/icloud-status?label=version)](https://github.com/aladac/icloud-status/releases)
[![Test](https://github.com/aladac/icloud-status/actions/workflows/test.yml/badge.svg)](https://github.com/aladac/icloud-status/actions/workflows/test.yml)

A macOS CLI tool to display comprehensive iCloud status information.

## Features

- Storage quota (human-readable format)
- Sync status (idle/syncing/disabled containers)
- Last sync time
- iCloud Drive size and location
- Desktop & Documents sync status
- Bird daemon status
- Network reachability
- Active containers with resolved app names
- Pending uploads/downloads
- Issue detection (stuck/failed syncs)

## Requirements

- macOS 12+
- Swift 5.9+
- [just](https://github.com/casey/just) (optional, for build commands)

## Installation

### Homebrew

```bash
brew install aladac/tap/icloud-status
```

### Using just

```bash
# Build and install to ~/bin
just install

# Or install globally
just install-global
```

### Manual

```bash
# Build
swift build -c release

# Copy to PATH
cp .build/release/icloud-status ~/bin/
```

## Usage

```bash
# Full status report
icloud-status

# Brief one-line status
icloud-status --brief
icloud-status -b

# Watch mode (auto-refresh)
icloud-status --watch
icloud-status -w

# Custom refresh interval (seconds)
icloud-status --watch --interval 10

# Raw brctl output
icloud-status --raw

# Disable colors
icloud-status --no-color

# Show help
icloud-status --help

# Show version
icloud-status --version
```

### Sample Output

```
╔══════════════════════════════════════╗
║         iCloud Status Report         ║
╚══════════════════════════════════════╝

STORAGE
─────────
  Remaining: 1.42 TB
  Account:   account=1234567890

SYNC STATUS
─────────────
  Total Containers:    91
  Idle (synced):       36
  Currently syncing:   0
  Disabled (no app):   55
  Last Sync:           2024-01-15 10:30:45

ICLOUD DRIVE
──────────────
  Location:   ~/Library/Mobile Documents/
  Total Size: 1.2G
  Containers: 91

DESKTOP & DOCUMENTS
─────────────────────
  Desktop:   Synced (156M)
  Documents: Synced (2.1G)

DAEMON STATUS
───────────────
  Bird:    Running (PID 12345)
  Network: Reachable

ACTIVE CONTAINERS
───────────────────
  • Keynote
  • Pages
  • Numbers
  • iCloud Drive
  • Mail
  ... and 5 more

ISSUES
────────
  None detected
```

### Brief Mode

```bash
$ icloud-status -b
iCloud: 1.42 TB free | 36/91 synced | Bird: ✓
```

## Development

```bash
# Build debug version
just build-debug

# Run with arguments
just run --brief

# Watch mode
just watch

# Update dependencies
just update

# Show dependency tree
just deps

# Clean build artifacts
just clean

# Run tests
just test
```

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) - CLI argument parsing
- [Rainbow](https://github.com/onevcat/Rainbow) - Terminal colors

## How It Works

Uses macOS's `brctl` (Bird Control) command-line tool to query iCloud status:

- `brctl quota` - Storage quota
- `brctl status` - Sync status of all containers
- `brctl dump` - Database info and sync times
- `brctl accounts` - Account information

## License

MIT
