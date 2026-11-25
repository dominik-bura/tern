import Foundation
import Darwin
import TernUpdateCore

do {
    let args = CommandLine.arguments
    guard args.count == 5, let pid = pid_t(args[3]), pid > 1 else { throw InstallationError.invalidBundle }
    let current = URL(fileURLWithPath: args[1]).standardizedFileURL
    let staged = URL(fileURLWithPath: args[2]).standardizedFileURL
    _ = try UpdateValidation.productionBundle(current)
    let deadline = Date().addingTimeInterval(30)
    while kill(pid, 0) == 0 {
        guard Date() < deadline else { throw InstallationError.timeout }
        Thread.sleep(forTimeInterval: 0.1)
    }
    try UpdateInstallation.install(current: current, staged: staged, expectedVersion: args[4]) { url in
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = [url.path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallationError.invalidBundle }
    }
} catch {
    // No browsing data is included. This file survives parent exit and is shown on relaunch.
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.dominikbura.tern")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? Data("Tern could not install the update. \(error.localizedDescription)".utf8).write(to: folder.appendingPathComponent("update-error.txt"), options: .atomic)
    FileHandle.standardError.write(Data("Tern update failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
