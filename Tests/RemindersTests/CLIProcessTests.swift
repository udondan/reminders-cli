import Foundation
import XCTest

/// Exercises the actual built `reminders` executable (not just `RemindersLibrary`), since
/// `main.swift`'s access-request wiring can only be verified by running the real binary.
final class CLIProcessTests: XCTestCase {
    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't find the products directory")
    }

    /// Regression test: running a subcommand that doesn't touch EventKit must not hang
    /// waiting on a Reminders access prompt that a headless session (e.g. CI) can never
    /// answer. Previously `main.swift` requested access unconditionally, hanging forever.
    func testGenerateCompletionScriptDoesNotHang() throws {
        let binary = productsDirectory.appendingPathComponent("reminders")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("reminders binary not found at \(binary.path)")
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--generate-completion-script", "zsh"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()

        let deadline = DispatchTime.now() + 10
        while process.isRunning && DispatchTime.now() < deadline {
            usleep(50_000)
        }

        if process.isRunning {
            process.terminate()
            XCTFail("reminders --generate-completion-script did not exit within 10s (hung)")
            return
        }

        XCTAssertEqual(process.terminationStatus, 0)
    }
}
