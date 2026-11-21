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

    /// Runs the binary with `arguments` and returns its exit status and stdout, or `nil` (after
    /// recording a failure) when it doesn't exit within 10 seconds.
    private func runBinary(
        _ arguments: [String], file: StaticString = #filePath, line: UInt = #line
    ) throws -> (status: Int32, stdout: Data)? {
        let binary = productsDirectory.appendingPathComponent("reminders")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("reminders binary not found at \(binary.path)")
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.standardOutput = try FileHandle(forWritingTo: output)
        process.standardError = FileHandle.nullDevice

        try process.run()

        let deadline = DispatchTime.now() + 10
        while process.isRunning && DispatchTime.now() < deadline {
            usleep(50_000)
        }

        if process.isRunning {
            process.terminate()
            XCTFail(
                "reminders \(arguments.joined(separator: " ")) did not exit within 10s (hung)",
                file: file, line: line)
            return nil
        }

        return (process.terminationStatus, try Data(contentsOf: output))
    }

    /// Regression test: running a subcommand that doesn't touch EventKit must not hang
    /// waiting on a Reminders access prompt that a headless session (e.g. CI) can never
    /// answer. Previously `main.swift` requested access unconditionally, hanging forever.
    func testGenerateCompletionScriptDoesNotHang() throws {
        guard let result = try runBinary(["--generate-completion-script", "zsh"]) else {
            return
        }
        XCTAssertEqual(result.status, 0)
    }

    /// `doctor` must report instead of requesting access, so it finishes even where no one can
    /// answer the prompt. Whether it exits 0 or 1 depends on the machine's authorization.
    func testDoctorDoesNotHangAndPrintsJSON() throws {
        guard let result = try runBinary(["doctor", "--format", "json"]) else {
            return
        }
        XCTAssertTrue([0, 1].contains(result.status), "unexpected exit status \(result.status)")
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
        XCTAssertNotNil(json["problems"] as? [Any])
        XCTAssertNotNil(json["authorization"] as? String)
    }
}
