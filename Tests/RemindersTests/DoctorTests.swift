import Foundation
@testable import RemindersLibrary
import XCTest

final class DoctorTests: XCTestCase {
    private let terminal = ParentProcess(name: "Terminal", isApplication: true)

    private func report(
        authorization: ReminderAuthorization,
        parentProcess: ParentProcess? = ParentProcess(name: "Terminal", isApplication: true),
        data: DoctorData? = nil
    ) -> DoctorReport {
        DoctorReport(
            version: "3.0.1", macOS: "15.4", macOSBuild: "24E248",
            binary: "/opt/homebrew/bin/reminders", architecture: "arm64",
            authorization: authorization, accessRequestAPI: .requestFullAccessToReminders,
            parentProcess: parentProcess, data: data)
    }

    private let healthyData = DoctorData(
        sources: [
            DoctorSource(title: "iCloud", listCount: 12), DoctorSource(title: "Local", listCount: 1),
        ],
        defaultList: DoctorDefaultList(title: "Reminders", sourceTitle: "iCloud"),
        openReminderCount: 87)

    private func jsonObject(_ report: DoctorReport) throws -> [String: Any] {
        let data = try JSONEncoder().encode(report)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Authorization

    func testRawStatusMapping() {
        XCTAssertEqual(ReminderAuthorization(rawStatus: 0), .notDetermined)
        XCTAssertEqual(ReminderAuthorization(rawStatus: 1), .restricted)
        XCTAssertEqual(ReminderAuthorization(rawStatus: 2), .denied)
        // Both the pre-macOS 14 `.authorized` and `.fullAccess` have raw value 3.
        XCTAssertEqual(ReminderAuthorization(rawStatus: 3), .fullAccess)
        XCTAssertEqual(ReminderAuthorization(rawStatus: 4), .writeOnly)
        XCTAssertEqual(ReminderAuthorization(rawStatus: 99), .unknown)
    }

    func testFullAccessWithDataIsHealthy() {
        let report = report(authorization: .fullAccess, data: healthyData)
        XCTAssertEqual(report.problems, [])
        XCTAssertTrue(report.isHealthy)
    }

    func testEveryMissingAccessStateIsAFailure() {
        let expected: [(ReminderAuthorization, DoctorProblem.Code)] = [
            (.denied, .accessDenied),
            (.restricted, .accessRestricted),
            (.notDetermined, .accessNotDetermined),
            (.writeOnly, .accessWriteOnly),
            (.unknown, .accessUnknown),
        ]
        for (authorization, code) in expected {
            let report = report(authorization: authorization)
            XCTAssertEqual(report.problems.map(\.code), [code], "\(authorization)")
            XCTAssertEqual(report.problems.first?.severity, .fail, "\(authorization)")
            XCTAssertFalse(report.isHealthy, "\(authorization)")
        }
    }

    func testDeniedSuggestionNamesTheParentApp() throws {
        let problem = try XCTUnwrap(report(authorization: .denied).problems.first)
        XCTAssertEqual(
            problem.suggestion,
            "Open System Settings > Privacy & Security > Reminders and enable access for "
                + "Terminal.app (the app that launched this command). Then re-run.")
    }

    func testSuggestionDoesNotNameANonAppParent() throws {
        let problem = try XCTUnwrap(
            report(authorization: .denied, parentProcess: ParentProcess(name: "sshd", isApplication: false))
                .problems.first)
        XCTAssertFalse(problem.suggestion.contains("sshd"))
        XCTAssertTrue(problem.suggestion.contains("the app that launched this command"))
    }

    func testNotDeterminedExplainsThePrompt() throws {
        let problem = try XCTUnwrap(report(authorization: .notDetermined).problems.first)
        XCTAssertTrue(problem.suggestion.contains("prompt only appears"))
        XCTAssertTrue(problem.suggestion.contains("from Terminal.app"))
    }

    // MARK: - Data checks

    func testNoListsAndNoDefaultListAreWarnings() {
        let report = report(
            authorization: .fullAccess,
            data: DoctorData(sources: [], defaultList: nil, openReminderCount: 0))
        XCTAssertEqual(report.problems.map(\.code), [.noLists, .noDefaultList])
        XCTAssertEqual(report.problems.map(\.severity), [.warn, .warn])
        XCTAssertTrue(report.isHealthy, "warnings alone must not fail doctor")
    }

    func testListCountSumsSources() {
        XCTAssertEqual(healthyData.listCount, 13)
    }

    func testSummarizeSourcesKeepsFirstAppearanceOrder() {
        XCTAssertEqual(
            summarizeSources(["iCloud", "Local", "iCloud", "iCloud"]),
            [DoctorSource(title: "iCloud", listCount: 3), DoctorSource(title: "Local", listCount: 1)])
        XCTAssertEqual(summarizeSources([]), [])
    }

    // MARK: - Plain output

    func testPlainOutputForHealthyReport() {
        XCTAssertEqual(
            formatDoctorReport(report(authorization: .fullAccess, data: healthyData)),
            [
                "OK    Version: reminders-cli 3.0.1",
                "OK    macOS: 15.4 (24E248)",
                "OK    Binary: /opt/homebrew/bin/reminders (arm64)",
                "OK    Parent process: Terminal.app",
                "OK    Reminders access: Full access",
                "OK    Access request API: requestFullAccessToReminders (macOS 14+)",
                "OK    Sources: iCloud (12 lists), Local (1 list)",
                "OK    Default list: Reminders (iCloud)",
                "OK    Reminders: 13 lists, 87 open reminders",
            ])
    }

    func testPlainOutputWithoutAccessSkipsDataChecksAndIndentsTheFix() {
        let lines = formatDoctorReport(report(authorization: .denied))
        XCTAssertEqual(lines.count, 7)
        XCTAssertEqual(lines[4], "FAIL  Reminders access: Denied")
        XCTAssertTrue(lines[5].hasPrefix("      Open System Settings"))
        XCTAssertFalse(lines.contains { $0.contains("Sources:") })
    }

    func testPlainOutputMarksWarnings() {
        let lines = formatDoctorReport(
            report(
                authorization: .fullAccess,
                data: DoctorData(
                    sources: [DoctorSource(title: "iCloud", listCount: 1)], defaultList: nil,
                    openReminderCount: 1)))
        XCTAssertTrue(lines.contains("WARN  Default list: none"))
        XCTAssertTrue(lines.contains("OK    Reminders: 1 list, 1 open reminder"))
    }

    func testUnknownParentProcess() {
        XCTAssertTrue(
            formatDoctorReport(report(authorization: .fullAccess, parentProcess: nil, data: healthyData))
                .contains("OK    Parent process: unknown"))
    }

    // MARK: - JSON output

    func testJSONWithFullAccess() throws {
        let json = try jsonObject(report(authorization: .fullAccess, data: healthyData))
        XCTAssertEqual(
            Set(json.keys),
            [
                "version", "macOS", "binary", "architecture", "authorization", "accessRequestAPI",
                "parentProcess", "sources", "defaultList", "listCount", "openReminderCount", "problems",
            ])
        XCTAssertEqual(json["authorization"] as? String, "fullAccess")
        XCTAssertEqual(json["accessRequestAPI"] as? String, "requestFullAccessToReminders")
        XCTAssertEqual(json["parentProcess"] as? String, "Terminal")
        XCTAssertEqual(json["defaultList"] as? String, "Reminders")
        XCTAssertEqual(json["listCount"] as? Int, 13)
        XCTAssertEqual(json["openReminderCount"] as? Int, 87)
        XCTAssertEqual((json["problems"] as? [Any])?.count, 0)
        let sources = try XCTUnwrap(json["sources"] as? [[String: Any]])
        XCTAssertEqual(sources.first?["title"] as? String, "iCloud")
        XCTAssertEqual(sources.first?["listCount"] as? Int, 12)
    }

    func testJSONWithoutAccessOmitsDataAndListsProblems() throws {
        let json = try jsonObject(report(authorization: .denied))
        for key in ["sources", "defaultList", "listCount", "openReminderCount"] {
            XCTAssertNil(json[key], key)
        }
        let problems = try XCTUnwrap(json["problems"] as? [[String: Any]])
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems[0]["code"] as? String, "access_denied")
        XCTAssertEqual(problems[0]["severity"] as? String, "fail")
        XCTAssertNotNil(problems[0]["message"] as? String)
        XCTAssertNotNil(problems[0]["suggestion"] as? String)
    }

    func testJSONDefaultListIsNullWhenNotConfigured() throws {
        let json = try jsonObject(
            report(
                authorization: .fullAccess,
                data: DoctorData(sources: [], defaultList: nil, openReminderCount: 0)))
        XCTAssertTrue(json["defaultList"] is NSNull)
    }

    // MARK: - Environment helpers

    func testFormatOSVersion() {
        XCTAssertEqual(
            formatOSVersion(OperatingSystemVersion(majorVersion: 15, minorVersion: 4, patchVersion: 0)),
            "15.4")
        XCTAssertEqual(
            formatOSVersion(OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 2)),
            "14.7.2")
    }

    func testApplicationNameFromExecutablePath() {
        XCTAssertEqual(
            applicationName(
                fromExecutablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            "Terminal")
        XCTAssertEqual(
            applicationName(
                fromExecutablePath:
                    "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"),
            "Visual Studio Code")
        XCTAssertNil(applicationName(fromExecutablePath: "/bin/zsh"))
        XCTAssertNil(applicationName(fromExecutablePath: "/usr/local/.app/tool"))
    }

    func testFindParentProcessWalksUpToTheApp() {
        let paths: [pid_t: String] = [
            300: "/bin/zsh",
            200: "/usr/bin/login",
            100: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
        ]
        let parents: [pid_t: pid_t] = [300: 200, 200: 100, 100: 1]
        XCTAssertEqual(
            findParentProcess(startingAt: 300, executablePath: { paths[$0] }, parentOf: { parents[$0] }),
            terminal)
    }

    func testFindParentProcessFallsBackToImmediateParent() {
        let paths: [pid_t: String] = [300: "/bin/zsh", 200: "/usr/sbin/sshd"]
        let parents: [pid_t: pid_t] = [300: 200, 200: 1]
        XCTAssertEqual(
            findParentProcess(startingAt: 300, executablePath: { paths[$0] }, parentOf: { parents[$0] }),
            ParentProcess(name: "zsh", isApplication: false))
    }

    func testFindParentProcessStopsOnCycles() {
        XCTAssertEqual(
            findParentProcess(startingAt: 5, executablePath: { _ in "/bin/sh" }, parentOf: { $0 == 5 ? 6 : 5 }),
            ParentProcess(name: "sh", isApplication: false))
    }
}
