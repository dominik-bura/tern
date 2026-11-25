import Foundation
import Darwin

struct CommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
    let timedOut: Bool
    var cancelled = false
}

final class CommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); defer { lock.unlock() }; stopped = true }
}

struct SecureCommandRunner: Sendable {
    func run(
        _ executable: URL,
        arguments: [String],
        timeout: TimeInterval = 30,
        currentDirectory: URL? = nil,
        environmentOverrides: [String: String] = [:],
        captureOutput: Bool = true,
        onOutputLine: (@Sendable (String) -> Void)? = nil,
        cancellation: CommandCancellation? = nil
    ) -> CommandResult {
        if cancellation?.isCancelled == true {
            return CommandResult(output: "", error: "Command cancelled", exitCode: -3, timedOut: false, cancelled: true)
        }
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let output = LockedData(capture: captureOutput, onLine: onOutputLine)
        let errors = LockedData()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in output.append(handle.availableData) }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in errors.append(handle.availableData) }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(output: "", error: error.localizedDescription, exitCode: -1, timedOut: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline, cancellation?.isCancelled != true {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let cancelled = process.isRunning && cancellation?.isCancelled == true
        let timedOut = process.isRunning && !cancelled
        if timedOut || cancelled {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        output.finishLines()
        errors.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        return CommandResult(
            output: String(decoding: output.value, as: UTF8.self),
            error: cancelled ? "Command cancelled" : timedOut ? "Command timed out" : String(decoding: errors.value, as: UTF8.self),
            exitCode: cancelled ? -3 : timedOut ? -2 : process.terminationStatus,
            timedOut: timedOut, cancelled: cancelled
        )
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private var pending = Data()
    private let capture: Bool
    private let onLine: (@Sendable (String) -> Void)?

    init(capture: Bool = true, onLine: (@Sendable (String) -> Void)? = nil) {
        self.capture = capture
        self.onLine = onLine
    }

    var value: Data {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if capture { storage.append(data) }
        if let onLine {
            pending.append(data)
            while let newline = pending.firstIndex(of: 10) {
                onLine(String(decoding: pending[..<newline], as: UTF8.self))
                pending.removeSubrange(...newline)
            }
        }
    }

    func finishLines() {
        lock.lock(); defer { lock.unlock() }
        if !pending.isEmpty { onLine?(String(decoding: pending, as: UTF8.self)); pending.removeAll() }
    }
}
