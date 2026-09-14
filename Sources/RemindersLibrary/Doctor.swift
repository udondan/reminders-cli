import Darwin
import Foundation

/// Reminders authorization as reported by `EKEventStore.authorizationStatus(for: .reminder)`.
/// Mapped from the raw value so the deprecated `.authorized` case (the same raw value as
/// macOS 14's `.fullAccess`) is never referenced, which would fail `-warnings-as-errors`.
enum ReminderAuthorization: String, Encodable {
    case notDetermined
    case restricted
    case denied
    case fullAccess
    case writeOnly
    case unknown

    init(rawStatus: Int) {
        switch rawStatus {
        case 0: self = .notDetermined
        case 1: self = .restricted
        case 2: self = .denied
        case 3: self = .fullAccess
        case 4: self = .writeOnly
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .notDetermined: return "Not determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .fullAccess: return "Full access"
        case .writeOnly: return "Write only"
        case .unknown: return "Unknown"
        }
    }
}

/// The EventKit call every other command uses to request access on this macOS version, mirroring
/// the `#available` branch in `Reminders.requestAccess()`.
enum AccessRequestAPI: String, Encodable {
    case requestFullAccessToReminders
    case requestAccess

    static var current: AccessRequestAPI {
        if #available(macOS 14.0, *) {
            return .requestFullAccessToReminders
        }
        return .requestAccess
    }

    var label: String {
        switch self {
        case .requestFullAccessToReminders: return "requestFullAccessToReminders (macOS 14+)"
        case .requestAccess: return "requestAccess(to:) (before macOS 14)"
        }
    }
}

/// Something `doctor` found wrong. `code` is the stable contract; `message` and `suggestion` are
/// prose. Deliberately not a `CLIError`: nothing is thrown, and these codes need no exit status.
struct DoctorProblem: Encodable, Equatable {
    enum Code: String, Encodable {
        case accessDenied = "access_denied"
        case accessRestricted = "access_restricted"
        case accessNotDetermined = "access_not_determined"
        case accessWriteOnly = "access_write_only"
        case accessUnknown = "access_unknown"
        case noLists = "no_lists"
        case noDefaultList = "no_default_list"
    }

    enum Severity: String, Encodable {
        case warn, fail
    }

    let code: Code
    let severity: Severity
    let message: String
    let suggestion: String
}

/// The closest ancestor process that TCC attributes Reminders access to: the first `.app` found
/// walking up from the parent, or else the immediate parent's executable (e.g. `sshd`).
struct ParentProcess: Equatable {
    let name: String
    let isApplication: Bool

    var displayName: String {
        isApplication ? "\(name).app" : name
    }
}

struct DoctorSource: Encodable, Equatable {
    let title: String
    let listCount: Int
}

struct DoctorDefaultList: Equatable {
    let title: String
    let sourceTitle: String?
}

/// What can only be read with full access. `nil` on the report when access is missing.
struct DoctorData: Equatable {
    let sources: [DoctorSource]
    let defaultList: DoctorDefaultList?
    let openReminderCount: Int

    var listCount: Int {
        sources.reduce(0) { $0 + $1.listCount }
    }
}

/// One line of the plain report.
struct DoctorCheck: Equatable {
    let label: String
    let value: String
    let problem: DoctorProblem?

    var status: String {
        switch problem?.severity {
        case .none: return "OK"
        case .warn: return "WARN"
        case .fail: return "FAIL"
        }
    }
}

struct DoctorReport: Encodable, Equatable {
    let version: String
    let macOS: String
    /// Plain output only.
    let macOSBuild: String?
    let binary: String
    let architecture: String
    let authorization: ReminderAuthorization
    let accessRequestAPI: AccessRequestAPI
    let parentProcess: ParentProcess?
    let data: DoctorData?

    /// Every check in report order, each carrying the problem it found, if any. `problems` and the
    /// plain output are both derived from this, so they can't disagree.
    var checks: [DoctorCheck] {
        let macOSValue = macOSBuild.map { "\(macOS) (\($0))" } ?? macOS
        var checks = [
            DoctorCheck(label: "Version", value: "reminders-cli \(version)", problem: nil),
            DoctorCheck(label: "macOS", value: macOSValue, problem: nil),
            DoctorCheck(label: "Binary", value: "\(binary) (\(architecture))", problem: nil),
            DoctorCheck(
                label: "Parent process", value: parentProcess?.displayName ?? "unknown", problem: nil),
            DoctorCheck(
                label: "Reminders access", value: authorization.label, problem: authorizationProblem),
            DoctorCheck(label: "Access request API", value: accessRequestAPI.label, problem: nil),
        ]
        guard let data else {
            return checks
        }

        let sourcesValue = data.sources.isEmpty
            ? "none"
            : data.sources.map { "\($0.title) (\(pluralized($0.listCount, "list")))" }
                .joined(separator: ", ")
        checks.append(
            DoctorCheck(
                label: "Sources", value: sourcesValue,
                problem: data.sources.isEmpty
                    ? DoctorProblem(
                        code: .noLists, severity: .warn,
                        message: "Reminders access works, but no reminder lists were found",
                        suggestion: "Create a list in Reminders.app first")
                    : nil))

        let defaultListValue = data.defaultList.map { list in
            list.sourceTitle.map { "\(list.title) (\($0))" } ?? list.title
        }
        checks.append(
            DoctorCheck(
                label: "Default list", value: defaultListValue ?? "none",
                problem: data.defaultList == nil
                    ? DoctorProblem(
                        code: .noDefaultList, severity: .warn,
                        message: "No default reminders list is configured",
                        suggestion: "Choose a default list in Reminders.app settings")
                    : nil))

        checks.append(
            DoctorCheck(
                label: "Reminders",
                value: "\(pluralized(data.listCount, "list")), "
                    + pluralized(data.openReminderCount, "open reminder"),
                problem: nil))
        return checks
    }

    var problems: [DoctorProblem] {
        checks.compactMap { $0.problem }
    }

    /// `doctor` exits 0 exactly when this is true; warnings don't count.
    var isHealthy: Bool {
        !problems.contains { $0.severity == .fail }
    }

    private var authorizationProblem: DoctorProblem? {
        // Name the app the grant belongs to when it's known; a bare executable like `sshd` isn't
        // something that can be picked in System Settings.
        let app = parentProcess.flatMap { $0.isApplication ? $0.displayName : nil }
        let grantee = app.map { "\($0) (the app that launched this command)" }
            ?? "the app that launched this command"
        let settings = "System Settings > Privacy & Security > Reminders"

        switch authorization {
        case .fullAccess:
            return nil
        case .denied:
            return DoctorProblem(
                code: .accessDenied, severity: .fail,
                message: "Reminders access was denied",
                suggestion: "Open \(settings) and enable access for \(grantee). Then re-run.")
        case .restricted:
            return DoctorProblem(
                code: .accessRestricted, severity: .fail,
                message: "Reminders access is restricted by a configuration profile or parental controls",
                suggestion: "Ask the administrator of this Mac to allow Reminders access for \(grantee)")
        case .notDetermined:
            return DoctorProblem(
                code: .accessNotDetermined, severity: .fail,
                message: "Reminders access has not been requested yet",
                suggestion: "The access prompt only appears when a command runs from an app that can "
                    + "show it. Run any command, e.g. 'reminders show-lists', once from \(app ?? "Terminal") "
                    + "and allow access. doctor never asks for access itself.")
        case .writeOnly:
            return DoctorProblem(
                code: .accessWriteOnly, severity: .fail,
                message: "Reminders access is write-only, so listing reminders returns nothing",
                suggestion: "Open \(settings) and give \(grantee) full access. Then re-run.")
        case .unknown:
            return DoctorProblem(
                code: .accessUnknown, severity: .fail,
                message: "Reminders reported an authorization status this version doesn't recognize",
                suggestion: "Check \(settings) for \(grantee)")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, macOS, binary, architecture, authorization, accessRequestAPI, parentProcess
        case sources, defaultList, listCount, openReminderCount, problems
    }

    /// The data keys are present only with full access; within them, `defaultList` is `null`
    /// when no default list is configured.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(macOS, forKey: .macOS)
        try container.encode(binary, forKey: .binary)
        try container.encode(architecture, forKey: .architecture)
        try container.encode(authorization, forKey: .authorization)
        try container.encode(accessRequestAPI, forKey: .accessRequestAPI)
        try container.encode(parentProcess?.name, forKey: .parentProcess)
        if let data {
            try container.encode(data.sources, forKey: .sources)
            try container.encode(data.defaultList?.title, forKey: .defaultList)
            try container.encode(data.listCount, forKey: .listCount)
            try container.encode(data.openReminderCount, forKey: .openReminderCount)
        }
        try container.encode(problems, forKey: .problems)
    }
}

/// Plain rendering of `doctor`: a status column wide enough for `WARN`/`FAIL`, then
/// `Label: value`, with the problem's suggestion indented under the line that found it.
func formatDoctorReport(_ report: DoctorReport) -> [String] {
    let indent = String(repeating: " ", count: 6)
    return report.checks.flatMap { check -> [String] in
        let status = check.status.padding(toLength: 6, withPad: " ", startingAt: 0)
        var lines = ["\(status)\(check.label): \(check.value)"]
        if let problem = check.problem {
            lines.append(indent + problem.suggestion)
        }
        return lines
    }
}

/// Number of lists per source title, in order of first appearance.
func summarizeSources(_ sourceTitles: [String]) -> [DoctorSource] {
    var order: [String] = []
    var counts: [String: Int] = [:]
    for title in sourceTitles {
        if counts[title] == nil {
            order.append(title)
        }
        counts[title, default: 0] += 1
    }
    return order.map { DoctorSource(title: $0, listCount: counts[$0] ?? 0) }
}

func formatOSVersion(_ version: OperatingSystemVersion) -> String {
    var formatted = "\(version.majorVersion).\(version.minorVersion)"
    if version.patchVersion != 0 {
        formatted += ".\(version.patchVersion)"
    }
    return formatted
}

/// The app bundle name in an executable path, taking the outermost bundle so a helper nested in
/// an app (`Visual Studio Code.app/.../Code Helper.app/...`) is attributed to the app itself.
func applicationName(fromExecutablePath path: String) -> String? {
    for component in path.split(separator: "/") where component.hasSuffix(".app") && component.count > 4 {
        return String(component.dropLast(4))
    }
    return nil
}

/// Walks up from `pid` until an ancestor's executable lives in an `.app`, stopping at launchd
/// (pid 1). Falls back to the executable name of `pid` itself. The lookups are injected so the
/// walk is testable without real processes.
func findParentProcess(
    startingAt pid: pid_t, executablePath: (pid_t) -> String?, parentOf: (pid_t) -> pid_t?
) -> ParentProcess? {
    var current = pid
    var visited = Set<pid_t>()
    while current > 1 && visited.insert(current).inserted {
        if let path = executablePath(current), let app = applicationName(fromExecutablePath: path) {
            return ParentProcess(name: app, isApplication: true)
        }
        guard let next = parentOf(current) else {
            break
        }
        current = next
    }
    return executablePath(pid).map {
        ParentProcess(name: URL(fileURLWithPath: $0).lastPathComponent, isApplication: false)
    }
}

// MARK: - Environment lookups

func detectParentProcess() -> ParentProcess? {
    findParentProcess(
        startingAt: getppid(), executablePath: executablePath(ofProcess:),
        parentOf: parentProcessId(of:))
}

private func executablePath(ofProcess pid: pid_t) -> String? {
    // PROC_PIDPATHINFO_MAXSIZE is a macro Swift doesn't import.
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
        return nil
    }
    return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
}

private func parentProcessId(of pid: pid_t) -> pid_t? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
        return nil
    }
    return pid_t(info.pbi_ppid)
}

func macOSBuildNumber() -> String? {
    var size = 0
    guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
        return nil
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else {
        return nil
    }
    return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
}

func currentExecutablePath() -> String {
    Bundle.main.executableURL?.resolvingSymlinksInPath().path
        ?? CommandLine.arguments.first
        ?? "unknown"
}

var currentArchitecture: String {
    #if arch(arm64)
        return "arm64"
    #elseif arch(x86_64)
        return "x86_64"
    #else
        return "unknown"
    #endif
}

private func pluralized(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
}
