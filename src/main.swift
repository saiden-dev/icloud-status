#!/usr/bin/env swift

import Foundation

// MARK: - Helpers

func shell(_ command: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/zsh"
    task.standardInput = nil

    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    task.waitUntilExit()
    return (output.trimmingCharacters(in: .whitespacesAndNewlines), task.terminationStatus)
}

func formatBytes(_ bytes: Int64) -> String {
    let tb = Double(bytes) / 1_099_511_627_776
    let gb = Double(bytes) / 1_073_741_824
    let mb = Double(bytes) / 1_048_576

    if tb >= 1 {
        return String(format: "%.2f TB", tb)
    } else if gb >= 1 {
        return String(format: "%.2f GB", gb)
    } else {
        return String(format: "%.2f MB", mb)
    }
}

func colorize(_ text: String, color: String) -> String {
    let colors: [String: String] = [
        "red": "\u{001B}[31m",
        "green": "\u{001B}[32m",
        "yellow": "\u{001B}[33m",
        "blue": "\u{001B}[34m",
        "magenta": "\u{001B}[35m",
        "cyan": "\u{001B}[36m",
        "white": "\u{001B}[37m",
        "bold": "\u{001B}[1m",
        "reset": "\u{001B}[0m"
    ]
    return "\(colors[color] ?? "")\(text)\(colors["reset"]!)"
}

func printHeader(_ title: String) {
    print("")
    print(colorize(title, color: "bold"))
    print(String(repeating: "─", count: title.count + 2))
}

// MARK: - iCloud Status Checks

func getQuota() -> (remaining: Int64, total: Int64)? {
    let result = shell("brctl quota 2>/dev/null")
    if let match = result.output.range(of: "\\d+", options: .regularExpression) {
        let bytesString = String(result.output[match])
        if let bytes = Int64(bytesString) {
            return (bytes, 0)
        }
    }
    return nil
}

func getSyncStatus() -> (total: Int, idle: Int, syncing: Int, disabled: Int, uploading: Int, downloading: Int) {
    let result = shell("brctl status 2>&1")
    let lines = result.output.components(separatedBy: "\n")

    var total = 0
    var idle = 0
    var syncing = 0
    var disabled = 0
    var uploading = 0
    var downloading = 0

    if let firstLine = lines.first,
       let match = firstLine.range(of: "\\d+", options: .regularExpression) {
        total = Int(String(firstLine[match])) ?? 0
    }

    for line in lines {
        if line.contains("client:idle") { idle += 1 }
        if line.contains("SYNC DISABLED") { disabled += 1 }
        if line.contains("uploading") { uploading += 1; syncing += 1 }
        if line.contains("downloading") { downloading += 1; syncing += 1 }
    }

    return (total, idle, syncing, disabled, uploading, downloading)
}

func getActiveContainers() -> [String] {
    let result = shell("brctl status 2>&1 | grep 'client:idle' | grep -v 'SYNC DISABLED' | head -15")
    var containers: [String] = []

    let lines = result.output.components(separatedBy: "\n")
    for line in lines {
        if let start = line.firstIndex(of: "<"),
           let end = line.firstIndex(of: "[") {
            var name = String(line[line.index(after: start)..<end])
            name = name.replacingOccurrences(of: #"\{\d+\}"#, with: "", options: .regularExpression)
            if !name.isEmpty {
                containers.append(name)
            }
        }
    }
    return containers
}

func getPendingItems() -> [(container: String, status: String, progress: String)] {
    let result = shell("brctl status 2>&1 | grep -E 'uploading|downloading'")
    var items: [(String, String, String)] = []

    let lines = result.output.components(separatedBy: "\n")
    for line in lines where !line.isEmpty {
        var status = "syncing"
        if line.contains("uploading") { status = "uploading" }
        if line.contains("downloading") { status = "downloading" }

        var progress = ""
        if let match = line.range(of: "\\d+%", options: .regularExpression) {
            progress = String(line[match])
        }

        if let start = line.firstIndex(of: "<"),
           let end = line.firstIndex(of: "[") {
            let name = String(line[line.index(after: start)..<end])
                .replacingOccurrences(of: #"\{\d+\}"#, with: "", options: .regularExpression)
            items.append((name, status, progress))
        }
    }
    return items
}

func getIssues() -> [String] {
    let result = shell("brctl status 2>&1 | grep -iE 'stuck|error|failed|timeout'")
    return result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
}

func getDriveSize() -> String {
    let result = shell("du -sh ~/Library/Mobile\\ Documents/ 2>/dev/null | awk '{print $1}'")
    return result.output.isEmpty ? "N/A" : result.output
}

func getDesktopDocumentsStatus() -> (desktop: (synced: Bool, size: String), documents: (synced: Bool, size: String)) {
    let desktopPath = shell("ls -d ~/Library/Mobile\\ Documents/com~apple~CloudDocs/Desktop 2>/dev/null")
    let desktopSynced = desktopPath.exitCode == 0
    let desktopSize = desktopSynced ? shell("du -sh ~/Library/Mobile\\ Documents/com~apple~CloudDocs/Desktop 2>/dev/null | awk '{print $1}'").output : "N/A"

    let docsPath = shell("ls -d ~/Library/Mobile\\ Documents/com~apple~CloudDocs/Documents 2>/dev/null")
    let docsSynced = docsPath.exitCode == 0
    let docsSize = docsSynced ? shell("du -sh ~/Library/Mobile\\ Documents/com~apple~CloudDocs/Documents 2>/dev/null | awk '{print $1}'").output : "N/A"

    return ((desktopSynced, desktopSize), (docsSynced, docsSize))
}

func getBirdStatus() -> (running: Bool, pid: String) {
    let result = shell("pgrep bird 2>/dev/null | head -1")
    return (!result.output.isEmpty, result.output)
}

func getNetworkStatus() -> Bool {
    let result = shell("nc -z -w 2 p123-quota.icloud.com 443 2>/dev/null")
    return result.exitCode == 0
}

func getLastSyncTime() -> String? {
    let result = shell("brctl dump 2>&1 | grep 'last-sync:' | head -1")
    if let match = result.output.range(of: "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", options: .regularExpression) {
        return String(result.output[match])
    }
    return nil
}

func getContainerCount() -> Int {
    let result = shell("ls ~/Library/Mobile\\ Documents/ 2>/dev/null | wc -l")
    return Int(result.output.trimmingCharacters(in: .whitespaces)) ?? 0
}

func getAccountInfo() -> String? {
    let result = shell("brctl dump 2>&1 | grep 'account=' | head -1")
    if let match = result.output.range(of: "account=\\d+", options: .regularExpression) {
        return String(result.output[match])
    }
    return nil
}

// MARK: - Container Name Mapping

func getContainerMapping() -> [String: String] {
    let result = shell("ls ~/Library/Mobile\\ Documents/ 2>/dev/null")
    var mapping: [String: String] = [:]

    let knownApps: [String: String] = [
        "garageband": "GarageBand",
        "imovie": "iMovie",
        "keynote": "Keynote",
        "pages": "Pages",
        "numbers": "Numbers",
        "whatsapp": "WhatsApp",
        "affinity": "Affinity",
        "kayak": "Kayak",
        "reddit": "Reddit",
        "mSecure": "mSecure",
        "eveuniverse": "EVE Universe",
        "CloudDocs": "iCloud Drive",
        "Notes": "Notes",
        "Preview": "Preview",
        "mail": "Mail",
        "Reminders": "Reminders",
        "Safari": "Safari",
        "Shortcuts": "Shortcuts",
        "TextEdit": "TextEdit",
        "VoiceMemos": "Voice Memos",
        "Automator": "Automator",
        "ScriptEditor": "Script Editor",
        "iBooks": "Books",
        "PhotoBooth": "Photo Booth",
        "QuickTime": "QuickTime",
        "freeform": "Freeform"
    ]

    for dir in result.output.components(separatedBy: "\n") {
        let parts = dir.components(separatedBy: "~")
        if parts.count >= 2 {
            let appPart = parts.last ?? ""
            let prefix = parts[0]

            for (key, name) in knownApps {
                if dir.lowercased().contains(key.lowercased()) {
                    mapping[prefix] = name
                    break
                }
            }

            if mapping[prefix] == nil && !appPart.isEmpty {
                mapping[prefix] = appPart.replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
            }
        }
    }

    return mapping
}

func resolveContainerName(_ raw: String, mapping: [String: String]) -> String {
    let cleaned = raw
        .replacingOccurrences(of: #"\{\d+\}"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)

    if cleaned.contains("cm.ae") || cleaned.contains("com.apple") {
        let appleApps: [String: String] = [
            "Keynote": "Keynote", "Ke": "Keynote",
            "Pages": "Pages", "Ps": "Pages",
            "Numbers": "Numbers", "Ns": "Numbers",
            "Notes": "Notes",
            "mail": "Mail", "ml": "Mail",
            "CloudDocs": "iCloud Drive", "Cs": "iCloud Drive",
            "Preview": "Preview", "Pw": "Preview",
            "Reminders": "Reminders",
            "Safari": "Safari",
            "Shortcuts": "Shortcuts",
            "freeform": "Freeform",
            "Automator": "Automator", "Ar": "Automator",
            "iBooks": "Books"
        ]

        for (key, name) in appleApps {
            if cleaned.contains(key) {
                return name
            }
        }
    }

    let parts = cleaned.components(separatedBy: ".")
    if let first = parts.first, let mapped = mapping[first] {
        return mapped
    }

    return cleaned
        .replacingOccurrences(of: "cm.ae.", with: "")
        .replacingOccurrences(of: "com.apple.", with: "")
}

// MARK: - Main

func main() {
    let containerMapping = getContainerMapping()

    print("")
    print(colorize("╔══════════════════════════════════════╗", color: "cyan"))
    print(colorize("║         iCloud Status Report         ║", color: "cyan"))
    print(colorize("╚══════════════════════════════════════╝", color: "cyan"))

    // Storage
    printHeader("STORAGE")
    if let quota = getQuota() {
        print("  Remaining: \(colorize(formatBytes(quota.remaining), color: "green"))")
    } else {
        print("  Remaining: \(colorize("Unable to fetch", color: "red"))")
    }

    if let account = getAccountInfo() {
        print("  Account:   \(account)")
    }

    // Sync Status
    printHeader("SYNC STATUS")
    let sync = getSyncStatus()
    print("  Total Containers:    \(sync.total)")
    print("  Idle (synced):       \(colorize("\(sync.idle)", color: "green"))")
    print("  Currently syncing:   \(sync.syncing > 0 ? colorize("\(sync.syncing)", color: "yellow") : "0")")
    if sync.uploading > 0 {
        print("    ↑ Uploading:       \(sync.uploading)")
    }
    if sync.downloading > 0 {
        print("    ↓ Downloading:     \(sync.downloading)")
    }
    print("  Disabled (no app):   \(colorize("\(sync.disabled)", color: "blue"))")

    if let lastSync = getLastSyncTime() {
        print("  Last Sync:           \(lastSync)")
    }

    // iCloud Drive
    printHeader("ICLOUD DRIVE")
    print("  Location:   ~/Library/Mobile Documents/")
    print("  Total Size: \(getDriveSize())")
    print("  Containers: \(getContainerCount())")

    // Desktop & Documents
    let ddStatus = getDesktopDocumentsStatus()
    printHeader("DESKTOP & DOCUMENTS")
    let desktopStatus = ddStatus.desktop.synced ? colorize("Synced", color: "green") : colorize("Local", color: "yellow")
    let docsStatus = ddStatus.documents.synced ? colorize("Synced", color: "green") : colorize("Local", color: "yellow")
    print("  Desktop:   \(desktopStatus) (\(ddStatus.desktop.size.isEmpty ? "0B" : ddStatus.desktop.size))")
    print("  Documents: \(docsStatus) (\(ddStatus.documents.size.isEmpty ? "0B" : ddStatus.documents.size))")

    // Daemon Status
    printHeader("DAEMON STATUS")
    let bird = getBirdStatus()
    let birdStatus = bird.running ? colorize("Running", color: "green") + " (PID \(bird.pid))" : colorize("Stopped", color: "red")
    print("  Bird:    \(birdStatus)")

    let network = getNetworkStatus()
    let networkStatus = network ? colorize("Reachable", color: "green") : colorize("Unreachable", color: "red")
    print("  Network: \(networkStatus)")

    // Active Containers
    printHeader("ACTIVE CONTAINERS")
    let containers = getActiveContainers()
    if containers.isEmpty {
        print("  No active containers")
    } else {
        for container in containers.prefix(12) {
            let name = resolveContainerName(container, mapping: containerMapping)
            print("  • \(name)")
        }
        if containers.count > 12 {
            print("  ... and \(containers.count - 12) more")
        }
    }

    // Pending Sync
    let pending = getPendingItems()
    if !pending.isEmpty {
        printHeader("PENDING SYNC")
        for item in pending {
            let icon = item.status == "uploading" ? "↑" : "↓"
            let progress = item.progress.isEmpty ? "" : " (\(item.progress))"
            print("  \(icon) \(resolveContainerName(item.container, mapping: containerMapping))\(progress)")
        }
    }

    // Issues
    let issues = getIssues()
    printHeader("ISSUES")
    if issues.isEmpty {
        print("  \(colorize("None detected", color: "green"))")
    } else {
        for issue in issues.prefix(5) {
            print("  \(colorize("⚠", color: "yellow")) \(issue)")
        }
    }

    print("")
}

main()
