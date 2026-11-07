import ArgumentParser
@testable import RemindersLibrary
import XCTest

final class CompletionTests: XCTestCase {
    /// List names with every character class the completion scripts treat specially.
    private let names = [
        "Work: Projects", ":lead", "it's \"q\"", "back\\slash", "cost $HOME", "run $(id)",
        "tick `id`", "~tilde", "{a,b}", "Einkäufe", "a-b_c.d/e",
    ]

    private func escaped(for shell: CompletionShell?) -> [String] {
        names.map { escapeCompletionCandidate($0, for: shell) }
    }

    func testZshEscapesBackslashAndColonOnly() {
        XCTAssertEqual(escaped(for: .zsh), [
            "Work\\: Projects", "\\:lead", "it's \"q\"", "back\\\\slash", "cost $HOME", "run $(id)",
            "tick `id`", "~tilde", "{a,b}", "Einkäufe", "a-b_c.d/e",
        ])
    }

    func testBashEscapesEveryShellCharacter() {
        XCTAssertEqual(escaped(for: .bash), [
            "Work\\:\\ Projects", "\\:lead", "it\\'s\\ \\\"q\\\"", "back\\\\slash",
            "cost\\ \\$HOME", "run\\ \\$\\(id\\)", "tick\\ \\`id\\`", "\\~tilde", "\\{a\\,b\\}",
            "Einkäufe", "a-b_c.d/e",
        ])
    }

    func testFishLeavesNamesUnchanged() {
        XCTAssertEqual(escaped(for: .fish), names)
    }

    func testNoShellLeavesNamesUnchanged() {
        XCTAssertEqual(escaped(for: nil), names)
    }
}
