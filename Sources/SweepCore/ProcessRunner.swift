import Foundation

struct ProcessOutput: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var errorText: String {
        let text = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : text
    }
}

enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> ProcessOutput? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        group.enter()
        DispatchQueue.global().async {
            stdoutData = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return nil
        }
        process.waitUntilExit()
        return ProcessOutput(status: process.terminationStatus, stdout: stdoutData, stderr: stderrData)
    }
}
