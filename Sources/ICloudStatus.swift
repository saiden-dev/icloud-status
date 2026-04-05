import ArgumentParser
import Foundation
import Rainbow

// MARK: - Spinner

class Spinner {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var frameIndex = 0
    private var isRunning = false
    private var message: String
    private var thread: Thread?

    init(_ message: String) {
        self.message = message
    }

    func start() {
        isRunning = true
        thread = Thread { [weak self] in
            while self?.isRunning == true {
                self?.render()
                Thread.sleep(forTimeInterval: 0.08)
            }
        }
        thread?.start()
    }

    func update(_ newMessage: String) {
        message = newMessage
    }

    func stop(success: Bool = true) {
        isRunning = false
        thread = nil
        // Clear the spinner line
        print("\r\u{001B}[K", terminator: "")
        fflush(stdout)
    }

    private func render() {
        let frame = frames[frameIndex % frames.count]
        print("\r\(frame.cyan) \(message)", terminator: "")
        fflush(stdout)
        frameIndex += 1
    }
}

// MARK: - CLI Command

@main
struct ICloudStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "icloud-status",
        abstract: "Display comprehensive iCloud status information",
        version: "0.1.3"
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
    let result = shell("brctl status 2>&1 | grep 'client:idle' | grep -v 'SYNC DISABLED'")
    var containers: [String] = []

    for line in result.output.components(separatedBy: "\n") {
        if let start = line.firstIndex(of: "<"),
           let end = line.firstIndex(of: "[") {
            let name = String(line[line.index(after: start)..<end])
            // Keep the raw format with {N} for proper resolution
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
    case synced(icloudSize: String, localSize: String)
    case symlink(localSize: String)
    case local(localSize: String)
    case notSynced
}

func getDesktopDocumentsStatus() -> (desktop: SyncState, documents: SyncState) {
    let icloudBase = "~/Library/Mobile\\ Documents/com~apple~CloudDocs"

    func checkFolder(_ name: String, localPath: String) -> SyncState {
        let icloudPath = "\(icloudBase)/\(name)"

        // Get local folder size
        let localSize = shell("du -sh \(localPath) 2>/dev/null | awk '{print $1}'").output
        let localSizeStr = localSize.isEmpty ? "N/A" : localSize

        // Check if path exists in iCloud
        let exists = shell("ls -d \(icloudPath) 2>/dev/null").exitCode == 0
        if !exists {
            return .local(localSize: localSizeStr)
        }

        // Check if it's a symlink
        let isSymlink = shell("test -L \(icloudPath) && echo yes").output == "yes"
        if isSymlink {
            return .symlink(localSize: localSizeStr)
        }

        // Real iCloud folder - get iCloud size
        let icloudSize = shell("du -sh \(icloudPath) 2>/dev/null | awk '{print $1}'").output
        let icloudSizeStr = icloudSize.isEmpty ? "0B" : icloudSize

        // Check if iCloud folder is empty/tiny but local has content
        // This indicates sync is not working properly
        return .synced(icloudSize: icloudSizeStr, localSize: localSizeStr)
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

    for dir in result.output.components(separatedBy: "\n") where !dir.isEmpty {
        // Format: TEAMID~reverse~bundle~id~AppName or com~apple~AppName
        let parts = dir.components(separatedBy: "~")
        guard parts.count >= 2 else { continue }

        let appName = resolveAppName(from: parts)

        // Build the obfuscated pattern that brctl uses
        // "57T9237FN3~net~whatsapp~WhatsApp" becomes "5{8}3.n{1}t.w{6}p.W{6}p"
        // We need to map "583.n1t.w6p.W6p" (our simplified version) to the app name
        var patternParts: [String] = []
        for part in parts {
            if part.count >= 2 {
                // Create pattern: first char + middle length + last char
                let pattern = "\(part.first!)\(part.count - 2)\(part.last!)"
                patternParts.append(pattern)
            } else if part.count == 1 {
                patternParts.append(part)
            }
        }
        let fullPattern = patternParts.joined(separator: ".")
        mapping[fullPattern] = appName

        // Also map just the team ID pattern (first part)
        if let firstPart = patternParts.first {
            mapping[firstPart] = appName
        }
    }

    return mapping
}

func resolveAppName(from parts: [String]) -> String {
    // Try to get name from installed app
    let bundleId = parts.dropFirst().joined(separator: ".").replacingOccurrences(of: "~", with: ".")

    // Check if app is installed and get its display name
    let mdfindResult = shell("mdfind \"kMDItemCFBundleIdentifier == '\(bundleId)'\" 2>/dev/null | head -1")
    if !mdfindResult.output.isEmpty {
        let nameResult = shell("defaults read \"\(mdfindResult.output)/Contents/Info\" CFBundleDisplayName 2>/dev/null || defaults read \"\(mdfindResult.output)/Contents/Info\" CFBundleName 2>/dev/null")
        let name = nameResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\u200e", with: "")
        if !name.isEmpty && !name.contains("does not exist") {
            return name
        }
    }

    // Fallback: parse from directory name
    let lastPart = parts.last ?? ""
    let cleaned = lastPart
        .replacingOccurrences(of: "10", with: "")
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")

    // Capitalize
    if cleaned.first?.isUppercase == true {
        return cleaned
    }
    return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
}

func resolveContainerName(_ raw: String, mapping: [String: String]) -> String {
    // Raw format: "5{8}3.n{1}t.w{6}p.W{6}p" where {N} = N hidden chars
    // Convert to: "583.n1t.w6p.W6p" for lookup

    let simplified = raw.replacingOccurrences(of: #"\{(\d+)\}"#, with: "$1", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)

    // Try full pattern match first
    if let name = mapping[simplified] {
        return name
    }

    // Try first part only (team ID)
    let parts = simplified.components(separatedBy: ".")
    if let first = parts.first, let name = mapping[first] {
        return name
    }

    // Apple apps fallback - map last meaningful part
    // c1m.a3e.K5e -> Keynote (K5e pattern)
    let appleApps: [String: String] = [
        "K5e": "Keynote", "P3s": "Pages", "N5s": "Numbers",
        "C7s": "iCloud Drive", "m2l": "Mail", "P5w": "Preview",
        "A7r": "Automator", "S7s": "Shortcuts", "N3s": "Notes",
        "R7s": "Reminders", "S4i": "Safari", "F6m": "Freeform",
        "i4s": "iCloud", "c7a": "Calendar", "Q14X": "QuickTime",
        "S11r": "Script Editor", "s5x": "Siri", "d1p": "DataProtection"
    ]

    for part in parts.reversed() {
        if let name = appleApps[part] {
            return name
        }
    }

    // Try partial match on last part
    if let lastPart = parts.last {
        for (key, name) in appleApps {
            if lastPart.hasPrefix(String(key.prefix(1))) && lastPart.hasSuffix(String(key.suffix(1))) {
                return name
            }
        }
    }

    // Last resort: return cleaned last part
    return parts.last ?? raw
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
    let spinner = Spinner("Loading iCloud status...")
    spinner.start()

    // Fetch all data first (slow operations)
    spinner.update("Fetching container info...")
    let containerMapping = getContainerMapping()

    spinner.update("Fetching sync status...")
    let sync = getSyncStatus()
    let containers = getActiveContainers()
    let pending = getPendingItems()
    let issues = getIssues()

    spinner.update("Fetching storage info...")
    let quota = getQuota()
    let accountInfo = getAccountInfo()
    let lastSync = getLastSyncTime()
    let driveSize = getDriveSize()
    let containerCount = getContainerCount()

    spinner.update("Checking system status...")
    let ddStatus = getDesktopDocumentsStatus()
    let bird = getBirdStatus()
    let network = getNetworkStatus()

    spinner.stop()

    print("")
    print("╔══════════════════════════════════════╗".cyan)
    print("║         iCloud Status Report         ║".cyan)
    print("╚══════════════════════════════════════╝".cyan)

    // Storage
    printHeader("STORAGE")
    if let q = quota {
        print("  Remaining: \(formatBytes(q).green)")
    } else {
        print("  Remaining: \("Unable to fetch".red)")
    }

    if let account = accountInfo {
        print("  Account:   \(account)")
    }

    // Sync Status
    printHeader("SYNC STATUS")
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

    if let ls = lastSync {
        print("  Last Sync:           \(ls)")
    }

    // iCloud Drive
    printHeader("ICLOUD DRIVE")
    print("  Location:   ~/Library/Mobile Documents/")
    print("  Total Size: \(driveSize)")
    print("  Containers: \(containerCount)")

    // Desktop & Documents
    printHeader("DESKTOP & DOCUMENTS")

    func formatSyncState(_ state: SyncState, name: String) -> String {
        switch state {
        case .synced(let icloudSize, let localSize):
            if icloudSize == "0B" && localSize != "0B" && localSize != "N/A" {
                return "  \(name):   \("Not syncing".yellow) (iCloud: \(icloudSize), Local: \(localSize))"
            }
            return "  \(name):   \("Synced".green) (\(icloudSize))"
        case .symlink(let localSize):
            return "  \(name):   \("Local".yellow) (\(localSize)) - symlink in iCloud"
        case .local(let localSize):
            return "  \(name):   \("Local".yellow) (\(localSize)) - not in iCloud"
        case .notSynced:
            return "  \(name):   \("Not configured".dim)"
        }
    }

    print(formatSyncState(ddStatus.desktop, name: "Desktop"))
    print(formatSyncState(ddStatus.documents, name: "Documents"))

    // Daemon Status
    printHeader("DAEMON STATUS")
    let birdStatus = bird.running ? "Running".green + " (PID \(bird.pid))" : "Stopped".red
    print("  Bird:    \(birdStatus)")
    print("  Network: \(network ? "Reachable".green : "Unreachable".red)")

    // Active Containers
    printHeader("ACTIVE CONTAINERS (\(containers.count))")
    if containers.isEmpty {
        print("  No active containers")
    } else {
        for container in containers {
            let name = resolveContainerName(container, mapping: containerMapping)
            print("  • \(name)")
        }
    }

    // Pending Sync
    if !pending.isEmpty {
        printHeader("PENDING SYNC")
        for item in pending {
            let icon = item.status == "uploading" ? "↑" : "↓"
            let progress = item.progress.isEmpty ? "" : " (\(item.progress))"
            print("  \(icon) \(resolveContainerName(item.container, mapping: containerMapping))\(progress)")
        }
    }

    // Issues
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
