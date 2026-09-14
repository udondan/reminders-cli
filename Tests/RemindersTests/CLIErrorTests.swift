import Foundation
@testable import RemindersLibrary
import XCTest

final class CLIErrorTests: XCTestCase {
    private struct UnderlyingError: LocalizedError {
        var errorDescription: String? { "disk is full" }
    }

    /// One representative error per code. The exhaustive switch makes the compiler flag any
    /// code that gets added without a sample here.
    private func sample(for code: CLIError.Code) -> CLIError {
        switch code {
        case .listNotFound: return .listNotFound("Groceries")
        case .listAmbiguous: return .listAmbiguous("Gro", matches: ["Groceries", "Grooming"])
        case .reminderNotFound: return .reminderNotFound(id: "ABC-123", listNameOrId: "Groceries")
        case .reminderAmbiguous: return .reminderAmbiguous(id: "ABC", matches: ["ABC-1", "ABC-2"])
        case .noDueDate: return .noDueDate()
        case .noSources: return .noSources()
        case .sourceNotFound: return .sourceNotFound("Work")
        case .sourceAmbiguous: return .sourceAmbiguous(["iCloud", "Exchange"])
        case .saveFailed: return .saveFailed(action: "add reminder", underlying: UnderlyingError())
        case .accessDenied: return .accessDenied(underlying: UnderlyingError())
        case .invalidArgument: return .invalidArgument("--repeat-until cannot be earlier than the due date")
        case .confirmationRequired:
            return .confirmationRequired(title: "Groceries", reminderCount: 14, completedCount: 3)
        }
    }

    private func decodedJSON(_ error: CLIError) throws -> [String: Any] {
        let rendered = error.rendered(format: .json)
        XCTAssertFalse(rendered.contains("\n"), "JSON must be a single line: \(rendered)")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any])
        return try XCTUnwrap(object["error"] as? [String: Any], "missing 'error' envelope in \(rendered)")
    }

    // MARK: - Every code

    func testEveryCodeHasASample() {
        for code in CLIError.Code.allCases {
            XCTAssertEqual(sample(for: code).code, code)
        }
    }

    func testPlainRenderingForEveryCode() {
        for code in CLIError.Code.allCases {
            let error = sample(for: code)
            let lines = error.rendered(format: .plain).components(separatedBy: "\n")
            XCTAssertEqual(lines.first, "Error: \(error.message)", "code \(code)")
            if let suggestion = error.suggestion {
                XCTAssertEqual(lines.count, 2, "code \(code)")
                XCTAssertEqual(lines.last, "Suggestion: \(suggestion)", "code \(code)")
            } else {
                XCTAssertEqual(lines.count, 1, "code \(code)")
            }
        }
    }

    func testJSONRenderingForEveryCode() throws {
        for code in CLIError.Code.allCases {
            let error = sample(for: code)
            let json = try decodedJSON(error)
            XCTAssertEqual(json["code"] as? String, code.rawValue, "code \(code)")
            XCTAssertEqual(json["message"] as? String, error.message, "code \(code)")
            if let suggestion = error.suggestion {
                XCTAssertEqual(json["suggestion"] as? String, suggestion, "code \(code)")
            } else {
                XCTAssertNil(json["suggestion"], "suggestion key must be absent for \(code)")
            }
        }
    }

    func testLocalizedDescriptionIsTheMessage() {
        for code in CLIError.Code.allCases {
            let error = sample(for: code)
            XCTAssertEqual(error.localizedDescription, error.message, "code \(code)")
        }
    }

    // MARK: - Exit statuses

    func testExitStatusesAreDistinctAndReserveTheConventionalOnes() {
        let statuses = CLIError.Code.allCases.map { sample(for: $0).exitCode.rawValue }
        XCTAssertEqual(Set(statuses).count, statuses.count, "exit statuses must be unique: \(statuses)")
        XCTAssertFalse(statuses.contains(0), "0 means success")
        XCTAssertFalse(statuses.contains(1), "1 is reserved for errors that are not a CLIError")
        XCTAssertFalse(statuses.contains(64), "64 is ArgumentParser's usage error status")
    }

    func testExitStatusMapping() {
        XCTAssertEqual(CLIError.listNotFound("x").exitCode.rawValue, 2)
        XCTAssertEqual(CLIError.listAmbiguous("x", matches: []).exitCode.rawValue, 3)
        XCTAssertEqual(CLIError.reminderNotFound(id: "x", listNameOrId: "l").exitCode.rawValue, 4)
        XCTAssertEqual(CLIError.reminderAmbiguous(id: "x", matches: []).exitCode.rawValue, 5)
        XCTAssertEqual(CLIError.noDueDate().exitCode.rawValue, 6)
        XCTAssertEqual(CLIError.noSources().exitCode.rawValue, 7)
        XCTAssertEqual(CLIError.sourceNotFound("x").exitCode.rawValue, 8)
        XCTAssertEqual(CLIError.sourceAmbiguous([]).exitCode.rawValue, 9)
        XCTAssertEqual(CLIError.saveFailed(action: "x", underlying: UnderlyingError()).exitCode.rawValue, 10)
        XCTAssertEqual(CLIError.accessDenied(underlying: nil).exitCode.rawValue, 11)
        XCTAssertEqual(CLIError.invalidArgument("x").exitCode.rawValue, 12)
    }

    // MARK: - Specific renderings

    func testJSONDoesNotEscapeSlashes() throws {
        let error = CLIError.invalidArgument("Use 'daily/weekly'")
        XCTAssertTrue(error.rendered(format: .json).contains("daily/weekly"))
    }

    func testJSONShapeIsStable() {
        let error = CLIError.listNotFound("Groceries")
        XCTAssertEqual(
            error.rendered(format: .json),
            "{\"error\":{\"code\":\"list_not_found\",\"message\":\"No reminders list matching 'Groceries'\","
                + "\"suggestion\":\"Run 'reminders show-lists' to see available lists and their IDs\"}}")
    }

    func testSaveFailedIncludesActionAndUnderlyingDescription() {
        let error = CLIError.saveFailed(action: "add reminder", underlying: UnderlyingError())
        XCTAssertEqual(error.message, "Failed to add reminder: disk is full")
        XCTAssertNil(error.suggestion)
    }

    func testAccessDeniedWithoutUnderlyingError() {
        let error = CLIError.accessDenied(underlying: nil)
        XCTAssertEqual(error.message, "Reminders access was not granted")
        XCTAssertNotNil(error.suggestion)
    }

    func testAccessDeniedWithUnderlyingError() {
        let error = CLIError.accessDenied(underlying: UnderlyingError())
        XCTAssertEqual(error.message, "Reminders access was not granted: disk is full")
    }

    func testNoDefaultListUsesListNotFoundCode() {
        XCTAssertEqual(CLIError.noDefaultList().code, .listNotFound)
    }

    func testListNotFoundNamesAvailableLists() {
        let error = CLIError.listNotFound("Grocery", available: ["Groceries", "Work"])
        XCTAssertEqual(error.message, "No reminders list matching 'Grocery'")
        XCTAssertEqual(
            error.suggestion, "Available lists: Groceries, Work (run 'reminders show-lists' for IDs)")
    }

    func testAmbiguousErrorsAreASingleLine() {
        for error in [
            CLIError.listAmbiguous("wor", matches: ["Work", "Work – Side projects"]),
            CLIError.reminderAmbiguous(id: "44C1", matches: ["44C1-1 (Buy milk)", "44C1-2 (Buy eggs)"]),
        ] {
            XCTAssertEqual(error.rendered(format: .plain).components(separatedBy: "\n").count, 2)
        }
    }

    func testSourceAmbiguousIsASingleLine() {
        let error = CLIError.sourceAmbiguous(["iCloud", "Exchange"])
        XCTAssertEqual(error.message, "Multiple sources hold reminder lists: iCloud, Exchange")
        XCTAssertEqual(error.rendered(format: .plain).components(separatedBy: "\n").count, 2)
    }
}
