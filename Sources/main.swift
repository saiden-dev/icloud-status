import ArgumentParser
import Foundation
import Rainbow

// MARK: - CLI Command

@main
struct ICloudStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "icloud-status",
        abstract: "Display comprehensive iCloud status information",
        version: "0.2.0"
    )

    @Flag(name: .shortAndLong, help: "Show raw brctl output")
    var raw = false

    @Flag(name: .shortAndLong, help: "Show only sync status summary")
    var brief = false

    @Flag(name: .shortAndLong, help: "Disable colored output")
    var noColor = false

    @Flag(name: .shortAndLong, help: "Watch mode - refresh every 5 seconds")
    var watch = false

    @Option(name: .shortAndLong, help: "Watch interval in seconds")
    var interval: Int = 5

    func run() throws {
        if noColor {
            Rainbow.enabled = false
        }

        if raw {
            showRawOutput()
            return
        }

        if watch {
            watchMode()
            return
        }

        if brief {
            showBriefStatus()
        } else {
            showFullStatus()
        }
    }

    func watchMode() {
        while true {
            print("\u{001B}[2J\u{001B}[H") // Clear screen
            showFullStatus()
            print("\n  Press Ctrl+C to exit. Refreshing in \(interval)s...".dim)
            Thread.sleep(forTimeInterval: Double(interval))
        }
    }
}

// MARK: - Shell Helper

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

// MARK: - Formatting

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

func printHeader(_ title: String) {
    print("")
    print(title.bold)
    print(String(repeating: "─", count: title.count + 2))
}

// MARK: - Data Fetching

struct SyncStatus {
    let total: Int
    let idle: Int
    let syncing: Int
    let disabled: Int
    let uploading: Int
    let downloading: Int
}

func getQuota() -> Int64? {
    let result = shell("brctl quota 2>/dev/null")
    if let match = result.output.range(of: "\\d+", options: .regularExpression) {
        return Int64(String(result.output[match]))
    }
    return nil
}

func getSyncStatus() -> SyncStatus {
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

    return SyncStatus(
        total: total, idle: idle, syncing: syncing,
        disabled: disabled, uploading: uploading, downloading: downloading
    )
}

func getActiveContainers() -> [String] {
    let result = shell("brctl status 2>&1 | grep 'client:idle' | grep -v 'SYNC DISABLED' | head -15")
    var containers: [String] = []

    for line in result.output.components(separatedBy: "\n") {
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

    for line in result.output.components(separatedBy: "\n") where !line.isEmpty {
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

enum SyncState {
    case synced(size: String)
    case symlink(size: String)
    case local(size: String)
    case notSynced
}

func getDesktopDocumentsStatus() -> (desktop: SyncState, documents: SyncState) {
    let icloudBase = "~/Library/Mobile\\ Documents/com~apple~CloudDocs"

    func checkFolder(_ name: String, localPath: String) -> SyncState {
        let icloudPath = "\(icloudBase)/\(name)"

        // Check if path exists in iCloud
        let exists = shell("ls -d \(icloudPath) 2>/dev/null").exitCode == 0
        if !exists {
            // Not in iCloud at all - check local size
            let localSize = shell("du -sh \(localPath) 2>/dev/null | awk '{print $1}'").output
            return .local(size: localSize.isEmpty ? "N/A" : localSize)
        }

        // Check if it's a symlink
        let isSymlink = shell("test -L \(icloudPath) && echo yes").output == "yes"
        if isSymlink {
            // It's a symlink - get local folder size
            let localSize = shell("du -sh \(localPath) 2>/dev/null | awk '{print $1}'").output
            return .symlink(size: localSize.isEmpty ? "N/A" : localSize)
        }

        // Real iCloud folder - get iCloud size (follow symlinks with -L)
        let icloudSize = shell("du -shL \(icloudPath) 2>/dev/null | awk '{print $1}'").output
        return .synced(size: icloudSize.isEmpty ? "0B" : icloudSize)
    }

    let desktop = checkFolder("Desktop", localPath: "~/Desktop")
    let documents = checkFolder("Documents", localPath: "~/Documents")

    return (desktop, documents)
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

// MARK: - Container Name Resolution

func getContainerMapping() -> [String: String] {
    let result = shell("ls ~/Library/Mobile\\ Documents/ 2>/dev/null")
    var mapping: [String: String] = [:]

    let knownApps: [String: String] = [
        "garageband": "GarageBand", "imovie": "iMovie", "keynote": "Keynote",
        "pages": "Pages", "numbers": "Numbers", "whatsapp": "WhatsApp",
        "affinity": "Affinity", "kayak": "Kayak", "reddit": "Reddit",
        "mSecure": "mSecure", "eveuniverse": "EVE Universe",
        "CloudDocs": "iCloud Drive", "Notes": "Notes", "Preview": "Preview",
        "mail": "Mail", "Reminders": "Reminders", "Safari": "Safari",
        "Shortcuts": "Shortcuts", "TextEdit": "TextEdit",
        "VoiceMemos": "Voice Memos", "Automator": "Automator",
        "ScriptEditor": "Script Editor", "iBooks": "Books",
        "PhotoBooth": "Photo Booth", "QuickTime": "QuickTime", "freeform": "Freeform"
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
                mapping[prefix] = appPart
                    .replacingOccurrences(of: "-", with: " ")
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
            "Notes": "Notes", "mail": "Mail", "ml": "Mail",
            "CloudDocs": "iCloud Drive", "Cs": "iCloud Drive",
            "Preview": "Preview", "Pw": "Preview",
            "Reminders": "Reminders", "Safari": "Safari",
            "Shortcuts": "Shortcuts", "freeform": "Freeform",
            "Automator": "Automator", "Ar": "Automator", "iBooks": "Books"
        ]

        for (key, name) in appleApps {
            if cleaned.contains(key) { return name }
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

// MARK: - Output Functions

func showRawOutput() {
    print("=== brctl quota ===".bold)
    print(shell("brctl quota 2>&1").output)
    print("\n=== brctl status ===".bold)
    print(shell("brctl status 2>&1").output)
}

func showBriefStatus() {
    let sync = getSyncStatus()
    let quota = getQuota()
    let bird = getBirdStatus()

    print("iCloud: ".bold, terminator: "")

    if let q = quota {
        print(formatBytes(q).green, terminator: " free | ")
    }

    print("\(sync.idle)/\(sync.total) synced".cyan, terminator: "")

    if sync.syncing > 0 {
        print(" | \(sync.syncing) syncing".yellow, terminator: "")
    }

    let issues = getIssues()
    if !issues.isEmpty {
        print(" | \(issues.count) issues".red, terminator: "")
    }

    print(" | Bird: ", terminator: "")
    print(bird.running ? "✓".green : "✗".red)
}

func showFullStatus() {
    let containerMapping = getContainerMapping()

    print("")
    print("╔══════════════════════════════════════╗".cyan)
    print("║         iCloud Status Report         ║".cyan)
    print("╚══════════════════════════════════════╝".cyan)

    // Storage
    printHeader("STORAGE")
    if let quota = getQuota() {
        print("  Remaining: \(formatBytes(quota).green)")
    } else {
        print("  Remaining: \("Unable to fetch".red)")
    }

    if let account = getAccountInfo() {
        print("  Account:   \(account)")
    }

    // Sync Status
    printHeader("SYNC STATUS")
    let sync = getSyncStatus()
    print("  Total Containers:    \(sync.total)")
    print("  Idle (synced):       \(String(sync.idle).green)")
    print("  Currently syncing:   \(sync.syncing > 0 ? String(sync.syncing).yellow : "0")")
    if sync.uploading > 0 {
        print("    ↑ Uploading:       \(sync.uploading)")
    }
    if sync.downloading > 0 {
        print("    ↓ Downloading:     \(sync.downloading)")
    }
    print("  Disabled (no app):   \(String(sync.disabled).blue)")

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

    func formatSyncState(_ state: SyncState, name: String) -> String {
        switch state {
        case .synced(let size):
            return "  \(name):   \("Synced".green) (\(size))"
        case .symlink(let size):
            return "  \(name):   \("Local".yellow) (\(size)) - symlink to ~/\(name)"
        case .local(let size):
            return "  \(name):   \("Local".yellow) (\(size)) - not synced"
        case .notSynced:
            return "  \(name):   \("Not configured".dim)"
        }
    }

    print(formatSyncState(ddStatus.desktop, name: "Desktop"))
    print(formatSyncState(ddStatus.documents, name: "Documents"))

    // Daemon Status
    printHeader("DAEMON STATUS")
    let bird = getBirdStatus()
    let birdStatus = bird.running ? "Running".green + " (PID \(bird.pid))" : "Stopped".red
    print("  Bird:    \(birdStatus)")

    let network = getNetworkStatus()
    print("  Network: \(network ? "Reachable".green : "Unreachable".red)")

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
            print("  ... and \(containers.count - 12) more".dim)
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
        print("  \("None detected".green)")
    } else {
        for issue in issues.prefix(5) {
            print("  \("⚠".yellow) \(issue)")
        }
    }

    print("")
}
