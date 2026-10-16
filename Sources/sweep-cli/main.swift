import Foundation
import SweepCore

let arguments = CommandLine.arguments.dropFirst()
let scope: ScanScope
switch arguments.first {
case nil, "disk": scope = .entireDisk
case "home": scope = .home
case let path?: scope = .folder(path)
}
let showAll = arguments.contains("--all")
let asJSON = arguments.contains("--json")

let formatter = ByteCountFormatter()
formatter.countStyle = .file
func human(_ bytes: Int64) -> String { formatter.string(fromByteCount: bytes) }

final class PhaseClock: @unchecked Sendable {
    let lock = NSLock()
    var marks: [String: Double] = [:]
    func mark(_ phase: ScanPhase, _ elapsed: Double) {
        lock.lock()
        if marks[phase.rawValue] == nil { marks[phase.rawValue] = elapsed }
        lock.unlock()
    }
}
let clock = PhaseClock()
let engine = SweepEngine()
let report = await engine.scan(scope: scope) { progress in
    clock.mark(progress.phase, progress.elapsed)
    guard !asJSON else { return }
    let line = String(format: "\r%@ · %d files · %d folders · %@ · %.1fs", progress.phase.rawValue, progress.filesScanned, progress.directoriesScanned, human(progress.bytesScanned), progress.elapsed)
    FileHandle.standardError.write(Data((line.padding(toLength: 100, withPad: " ", startingAt: 0)).utf8))
}

if asJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try encoder.encode(report.items))
    exit(0)
}

let stats = report.stats
let rate = Double(stats.files) / max(stats.duration, 0.001)
print("\n\nScanned \(stats.files) files in \(stats.directories) folders (\(human(stats.bytes))) in \(String(format: "%.2f", stats.duration)) s · \(Int(rate)) files/s · \(stats.inaccessibleDirectories) folders not readable")
print("Phase starts: " + clock.marks.sorted { $0.value < $1.value }.map { "\($0.key) @ \(String(format: "%.2f", $0.value))s" }.joined(separator: ", "))
print("Full Disk Access: \(SweepEngine.hasFullDiskAccess() ? "yes" : "no") · Docker: installed \(report.docker.installed), running \(report.docker.running)")
print("Tree nodes: \(report.tree.nodeCount) · root \(human(report.tree.root.size))")

let byCategory = Dictionary(grouping: report.items, by: \.category)
let total = report.items.reduce(0) { $0 + $1.size }
let recommended = report.items.filter(\.recommended).reduce(0) { $0 + $1.size }
print("Junk found: \(human(total)) in \(report.items.count) items · recommended \(human(recommended))\n")
for (category, items) in byCategory.sorted(by: { $0.value.reduce(0) { $0 + $1.size } > $1.value.reduce(0) { $0 + $1.size } }) {
    let sum = items.reduce(0) { $0 + $1.size }
    print("■ \(category.title): \(human(sum)) (\(items.count))")
    for item in items.prefix(showAll ? items.count : 6) {
        let flag = item.recommended ? "✓" : " "
        print("   \(flag) [\(item.safety)] \(human(item.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.title) — \(item.detail)\(item.path.map { " · " + $0 } ?? "")")
    }
}
