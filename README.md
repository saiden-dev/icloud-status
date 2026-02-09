# icloud-status

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

- macOS (uses `brctl` - Bird Control)
- Swift 5.x
- [just](https://github.com/casey/just) (optional, for build commands)

## Installation

### Using just

```bash
# Build and install to ~/bin
just install

# Or install globally
just install-global
```

### Manual

```bash
# Compile
swiftc -O -o icloud-status src/main.swift

# Copy to PATH
cp icloud-status ~/bin/
```

## Usage

```bash
icloud-status
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

## Development

```bash
# Build debug version
just build-debug

# Run without compiling (as script)
just script

# Check syntax
just check

# Clean build artifacts
just clean
```

## How It Works

Uses macOS's `brctl` (Bird Control) command-line tool to query iCloud status:

- `brctl quota` - Storage quota
- `brctl status` - Sync status of all containers
- `brctl dump` - Database info and sync times
- `brctl accounts` - Account information

## License

MIT
