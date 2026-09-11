# Claude Usage Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that shows Claude subscription usage (`42% · 62% · 93%`) with a details dropdown, fed by `claude -p "/usage"`.

**Architecture:** A Swift package with a UI-free `UsageCore` library (parser, process runner, fetcher, store, menu bar label logic) that is fully unit-tested, and a thin `ClaudeUsage` AppKit/SwiftUI executable (status item, popover, login item). `build.sh` wraps the executable into an ad-hoc-signed `.app`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, AppKit (`NSStatusItem`, `NSPopover`), SwiftUI, Observation, ServiceManagement, Swift Testing. Built with Xcode 27's toolchain via `DEVELOPER_DIR`.

**Spec:** `docs/superpowers/specs/2026-09-11-claude-usage-menubar-design.md`

## Global Constraints

- Deployment target macOS 14 (`.macOS(.v14)`); `// swift-tools-version:6.0`; Swift 6 language mode (strict concurrency errors must be fixed, not suppressed).
- No third-party dependencies.
- App name `Claude Usage`, executable `ClaudeUsage`, bundle id `local.roald.ClaudeUsage`, `LSUIElement = true`.
- The usage command is exactly: `claude -p /usage --no-session-persistence --output-format json`.
- Thresholds: `warning` from 80%, `critical` from 95% (percent shown rounded **down**).
- Refresh every 5 minutes, on popover open, and on wake from sleep. Fetch timeout 30 s; login-shell lookup timeout 10 s.
- Menu bar separator is ` · ` (space, U+00B7, space). Loading placeholder is `–` (U+2013). Warning sign is `⚠︎` (U+26A0 U+FE0E).
- Always build and test through `./build.sh` / `./test.sh`; they set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` unless already set. Bare `swift test` fails on this machine (Command Line Tools lack working test frameworks). Never run `xcode-select -s`.
- Never write to `~/.claude`. Tests must not call the real `claude` except the opt-in end-to-end test.

## File Map

```
Package.swift                              targets: UsageCore, ClaudeUsage (Task 6), UsageCoreTests
.gitignore
test.sh                                    swift test with Xcode toolchain
build.sh                                   release build → build/Claude Usage.app; `install` → /Applications
README.md                                  how to build/install/test
Resources/Info.plist                       bundle metadata, LSUIElement
Sources/UsageCore/Limit.swift              Limit value type
Sources/UsageCore/UsageParser.swift        /usage text → [Limit]
Sources/UsageCore/UsageError.swift         error enum + user-facing messages + sample helper
Sources/UsageCore/ProcessRunner.swift      run a process with timeout (internal)
Sources/UsageCore/ClaudeLocator.swift      find the claude executable
Sources/UsageCore/UsageFetcher.swift       run claude, decode JSON → result text
Sources/UsageCore/UsageStore.swift         @Observable state + refresh logic
Sources/UsageCore/MenuBarLabel.swift       Level, Segment, label/tooltip/threshold logic
Sources/ClaudeUsage/ClaudeUsageMain.swift  @main entry
Sources/ClaudeUsage/AppDelegate.swift      wiring: store, status item, wake observer, login item
Sources/ClaudeUsage/StatusItemController.swift  NSStatusItem rendering + popover
Sources/ClaudeUsage/LevelColors.swift      Level → NSColor / SwiftUI Color
Sources/ClaudeUsage/DropdownView.swift     popover content (LimitRow, ErrorBanner)
Sources/ClaudeUsage/LoginItem.swift        open-at-login toggle
Tests/UsageCoreTests/Fixtures.swift        real /usage output
Tests/UsageCoreTests/TestSupport.swift     makeScript helper
Tests/UsageCoreTests/*Tests.swift          one file per UsageCore unit
```

---

### Task 1: Package scaffold and UsageParser

**Files:**
- Create: `Package.swift`, `.gitignore`, `test.sh`, `Sources/UsageCore/Limit.swift`, `Sources/UsageCore/UsageParser.swift`
- Test: `Tests/UsageCoreTests/Fixtures.swift`, `Tests/UsageCoreTests/UsageParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct Limit: Equatable, Sendable { label: String; shortName: String; percent: Double; resetText: String }` with memberwise `public init(label:shortName:percent:resetText:)`.
  - `public enum UsageParser { public static func parse(_ text: String) -> [Limit]; static func shortName(for name: String) -> String }`
  - `enum Fixtures { static let usageOutput: String }` (test target).

- [ ] **Step 1: Create the package scaffold**

`Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageCore"),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
```

`.gitignore`:
```
.build/
build/
.swiftpm/
```

`test.sh`:
```bash
#!/bin/bash
# Runs the tests with Xcode's toolchain; the Command Line Tools can't run Swift Testing.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec swift test "$@"
```
Run: `chmod +x test.sh`

`Sources/UsageCore/Limit.swift`:
```swift
/// One usage limit as reported by `/usage`, e.g. "Current week (Fable)" at 93%.
public struct Limit: Equatable, Sendable {
    public let label: String
    public let shortName: String
    public let percent: Double
    public let resetText: String

    public init(label: String, shortName: String, percent: Double, resetText: String) {
        self.label = label
        self.shortName = shortName
        self.percent = percent
        self.resetText = resetText
    }
}
```

- [ ] **Step 2: Write the fixture and failing parser tests**

`Tests/UsageCoreTests/Fixtures.swift` (the separators are U+00B7 middle dots, exactly as Claude Code prints them):
```swift
enum Fixtures {
    /// Real `/usage` output from Claude Code 2.1.269 on 2026-09-11, cut short after the
    /// start of the contributions section (which also contains `%` and `·`, and must be ignored).
    static let usageOutput = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 42% used · resets Sep 12 at 12am (Europe/Amsterdam)
    Current week (all models): 62% used · resets Sep 13 at 9pm (Europe/Amsterdam)
    Current week (Fable): 93% used · resets Sep 13 at 9pm (Europe/Amsterdam)

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine — does not include other devices or claude.ai.

    Last 24h · 1010 requests · 19 sessions
      47% of your usage was at >150k context
      19% of your usage came from subagent-heavy sessions
    """
}
```

`Tests/UsageCoreTests/UsageParserTests.swift`:
```swift
import Testing
@testable import UsageCore

@Suite struct UsageParserTests {
    @Test func parsesRealOutput() {
        #expect(UsageParser.parse(Fixtures.usageOutput) == [
            Limit(label: "Current session", shortName: "Session", percent: 42, resetText: "resets Sep 12 at 12am"),
            Limit(label: "Current week (all models)", shortName: "Week", percent: 62, resetText: "resets Sep 13 at 9pm"),
            Limit(label: "Current week (Fable)", shortName: "Fable", percent: 93, resetText: "resets Sep 13 at 9pm"),
        ])
    }

    @Test func missingModelLimitIsSimplyAbsent() {
        let text = """
        Current session: 42% used · resets Sep 12 at 12am (Europe/Amsterdam)
        Current week (all models): 62% used · resets Sep 13 at 9pm (Europe/Amsterdam)
        """
        #expect(UsageParser.parse(text).map(\.shortName) == ["Session", "Week"])
    }

    @Test func extraLimitIsIncludedInOrder() {
        let text = Fixtures.usageOutput + "\nCurrent week (Sonnet): 10% used · resets Sep 14 at 1am (Europe/Amsterdam)"
        #expect(UsageParser.parse(text).map(\.shortName) == ["Session", "Week", "Fable", "Sonnet"])
    }

    @Test func rewordedOutputYieldsNoLimits() {
        let text = """
        Session usage: 42% (resets Sep 12)
        Weekly usage: 62%
        """
        #expect(UsageParser.parse(text).isEmpty)
    }

    @Test func decimalPercentage() {
        let limits = UsageParser.parse("Current session: 42.5% used · resets Sep 12 at 12am")
        #expect(limits.map(\.percent) == [42.5])
    }

    @Test func resetWithoutTimezoneIsKeptAsIs() {
        let limits = UsageParser.parse("Current session: 42% used · resets Sep 12 at 12am")
        #expect(limits.map(\.resetText) == ["resets Sep 12 at 12am"])
    }

    @Test(arguments: zip(["session", "week (all models)", "week (Fable)"], ["Session", "Week", "Fable"]))
    func shortNames(name: String, expected: String) {
        #expect(UsageParser.shortName(for: name) == expected)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./test.sh --filter UsageParserTests`
Expected: build FAILS with `cannot find 'UsageParser' in scope`.

- [ ] **Step 4: Implement the parser**

`Sources/UsageCore/UsageParser.swift`:
```swift
import Foundation

/// Turns the human-readable text of Claude Code's `/usage` command into limits.
public enum UsageParser {
    /// Matches lines like `Current week (Fable): 93% used · resets Sep 13 at 9pm (Europe/Amsterdam)`
    /// and ignores everything else. Returns an empty array when nothing matches.
    public static func parse(_ text: String) -> [Limit] {
        text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> Limit? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard
            let match = trimmed.wholeMatch(
                of: /Current (?<name>[^:]+): (?<percent>\d+(?:\.\d+)?)% used · (?<reset>resets .+)/),
            let percent = Double(match.output.percent)
        else { return nil }

        let name = String(match.output.name)
        return Limit(
            label: "Current \(name)",
            shortName: shortName(for: name),
            percent: percent,
            resetText: String(match.output.reset).replacing(/\s*\([^)]*\)$/, with: ""))
    }

    /// "week (Fable)" → "Fable", "week (all models)" → "Week", "session" → "Session".
    static func shortName(for name: String) -> String {
        if let match = name.firstMatch(of: /\((?<inner>[^)]+)\)/), match.output.inner != "all models" {
            return String(match.output.inner)
        }
        let firstWord = name.split(separator: " ").first.map(String.init) ?? name
        return firstWord.prefix(1).uppercased() + firstWord.dropFirst()
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./test.sh --filter UsageParserTests`
Expected: PASS, 9 tests (7 functions, one with 3 arguments).

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore test.sh Sources/UsageCore Tests/UsageCoreTests
git commit -m "feat: add package scaffold and /usage parser"
```

---

### Task 2: UsageError, ProcessRunner and ClaudeLocator

**Files:**
- Create: `Sources/UsageCore/UsageError.swift`, `Sources/UsageCore/ProcessRunner.swift`, `Sources/UsageCore/ClaudeLocator.swift`
- Test: `Tests/UsageCoreTests/TestSupport.swift`, `Tests/UsageCoreTests/UsageErrorTests.swift`, `Tests/UsageCoreTests/ClaudeLocatorTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `public enum UsageError: Error, Equatable, Sendable` with cases `notFound(searched: [String])`, `claudeError(message: String)`, `timedOut`, `unreadableOutput(sample: String)`, `unparseable(sample: String)`; `public var message: String`; `public var detail: String?`; `public static func sample(of text: String) -> String`.
  - `struct ProcessOutput: Sendable { status: Int32; stdout: Data; stderr: Data }`
  - `enum ProcessRunner { enum Failure: Error, Equatable { case launchFailed, timedOut }; static func run(_ executable: URL, arguments: [String], workingDirectory: URL? = nil, environment: [String: String]? = nil, timeout: TimeInterval) -> Result<ProcessOutput, Failure> }`
  - `public enum ClaudeLocator { public static func locate() -> Result<URL, UsageError>; static func fallbackPaths(home: String = NSHomeDirectory()) -> [String]; static func firstExecutable(in paths: [String]) -> Result<URL, UsageError>; static func lookUpViaLoginShell(shell: URL = URL(fileURLWithPath: "/bin/zsh")) -> String? }`
  - Test helper `func makeScript(_ body: String, name: String = "claude") throws -> URL`.

- [ ] **Step 1: Write the test helper and failing tests**

`Tests/UsageCoreTests/TestSupport.swift`:
```swift
import Foundation

/// Writes an executable `/bin/sh` script named `name` into a fresh temporary directory.
func makeScript(_ body: String, name: String = "claude") throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}
```

`Tests/UsageCoreTests/UsageErrorTests.swift`:
```swift
import Testing
@testable import UsageCore

@Suite struct UsageErrorTests {
    @Test func sampleKeepsFirstFiveNonEmptyLines() {
        #expect(UsageError.sample(of: "a\n\nb\n  c  \nd\ne\nf\n") == "a\nb\nc\nd\ne")
    }

    @Test func notFoundListsSearchedLocations() {
        let error = UsageError.notFound(searched: ["/a/claude", "/b/claude"])
        #expect(error.message == "Couldn't find the claude command")
        #expect(error.detail == "Looked in: /a/claude, /b/claude")
    }

    @Test func claudeErrorShowsClaudesMessage() {
        let error = UsageError.claudeError(message: "Login expired · run /login")
        #expect(error.message == "Login expired · run /login")
        #expect(error.detail == nil)
    }

    @Test func unparseableShowsSample() {
        let error = UsageError.unparseable(sample: "Something else")
        #expect(error.message == "Couldn't read usage; the /usage format may have changed")
        #expect(error.detail == "Something else")
    }
}
```

`Tests/UsageCoreTests/ClaudeLocatorTests.swift`:
```swift
import Foundation
import Testing
@testable import UsageCore

@Suite struct ClaudeLocatorTests {
    @Test func fallbackPathsUseHome() {
        #expect(ClaudeLocator.fallbackPaths(home: "/Users/test") == [
            "/Users/test/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
        ])
    }

    @Test func firstExecutablePicksFirstExistingPath() throws {
        let script = try makeScript("exit 0")
        let result = ClaudeLocator.firstExecutable(in: ["/nonexistent/claude", script.path])
        #expect(result.map(\.path) == .success(script.path))
    }

    @Test func firstExecutableReportsSearchedPaths() {
        #expect(ClaudeLocator.firstExecutable(in: ["/a/claude", "/b/claude"])
            == .failure(.notFound(searched: ["your login shell's PATH", "/a/claude", "/b/claude"])))
    }

    @Test func loginShellLookupTakesLastOutputLine() throws {
        let shell = try makeScript("echo 'welcome from .zprofile'\necho /opt/tools/claude", name: "zsh")
        #expect(ClaudeLocator.lookUpViaLoginShell(shell: shell) == "/opt/tools/claude")
    }

    @Test func loginShellLookupFailureReturnsNil() throws {
        let shell = try makeScript("exit 1", name: "zsh")
        #expect(ClaudeLocator.lookUpViaLoginShell(shell: shell) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter "UsageErrorTests|ClaudeLocatorTests"`
Expected: build FAILS with `cannot find 'UsageError' in scope` / `cannot find 'ClaudeLocator' in scope`.

- [ ] **Step 3: Implement UsageError**

`Sources/UsageCore/UsageError.swift`:
```swift
import Foundation

/// Everything that can go wrong while getting usage, with the text the dropdown shows for it.
public enum UsageError: Error, Equatable, Sendable {
    case notFound(searched: [String])
    case claudeError(message: String)
    case timedOut
    case unreadableOutput(sample: String)
    /// The command succeeded but no usage lines were recognised. Set only by `UsageStore`.
    case unparseable(sample: String)

    public var message: String {
        switch self {
        case .notFound: "Couldn't find the claude command"
        case .claudeError(let message): message
        case .timedOut: "Claude Code didn't respond"
        case .unreadableOutput: "Couldn't read Claude Code's output"
        case .unparseable: "Couldn't read usage; the /usage format may have changed"
        }
    }

    public var detail: String? {
        switch self {
        case .notFound(let searched): "Looked in: " + searched.joined(separator: ", ")
        case .unreadableOutput(let sample), .unparseable(let sample): sample
        case .claudeError, .timedOut: nil
        }
    }

    /// The first few non-empty lines of `text`, for showing unexpected output.
    public static func sample(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Implement ProcessRunner**

`Sources/UsageCore/ProcessRunner.swift`:
```swift
import Foundation

struct ProcessOutput: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

enum ProcessRunner {
    enum Failure: Error, Equatable {
        case launchFailed
        case timedOut
    }

    /// Runs a process to completion, blocking the calling thread. Output is read after the process
    /// exits, which is fine for the few KB used here: pipe buffers hold 64 KB before a writer blocks.
    static func run(
        _ executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) -> Result<ProcessOutput, Failure> {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        if let environment { process.environment = environment }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return .failure(.launchFailed)
        }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return .failure(.timedOut)
        }
        return .success(ProcessOutput(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()))
    }
}
```

- [ ] **Step 5: Implement ClaudeLocator**

`Sources/UsageCore/ClaudeLocator.swift`:
```swift
import Foundation

/// Finds the `claude` executable. Apps started from Finder don't get the shell's PATH,
/// so ask the login shell first, then try the usual install locations.
public enum ClaudeLocator {
    public static func locate() -> Result<URL, UsageError> {
        if let path = lookUpViaLoginShell(), FileManager.default.isExecutableFile(atPath: path) {
            return .success(URL(fileURLWithPath: path))
        }
        return firstExecutable(in: fallbackPaths())
    }

    static func fallbackPaths(home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    }

    static func firstExecutable(in paths: [String]) -> Result<URL, UsageError> {
        if let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return .success(URL(fileURLWithPath: path))
        }
        return .failure(.notFound(searched: ["your login shell's PATH"] + paths))
    }

    /// Runs `command -v claude` in a login shell. Takes the last output line, since shell
    /// startup files sometimes print a greeting first.
    static func lookUpViaLoginShell(shell: URL = URL(fileURLWithPath: "/bin/zsh")) -> String? {
        guard
            case .success(let output) = ProcessRunner.run(shell, arguments: ["-lc", "command -v claude"], timeout: 10),
            output.status == 0
        else { return nil }
        return String(decoding: output.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./test.sh`
Expected: PASS, all UsageParser, UsageError and ClaudeLocator tests (18 total).

- [ ] **Step 7: Commit**

```bash
git add Sources/UsageCore Tests/UsageCoreTests
git commit -m "feat: add error type, process runner and claude locator"
```

---

### Task 3: UsageFetcher

**Files:**
- Create: `Sources/UsageCore/UsageFetcher.swift`
- Test: `Tests/UsageCoreTests/UsageFetcherTests.swift`

**Interfaces:**
- Consumes: `ClaudeLocator.locate`, `ProcessRunner.run`, `UsageError`, `UsageError.sample(of:)` (Task 2); `UsageParser.parse` (Task 1, e2e test only); `makeScript` (test helper).
- Produces:
  - `public struct UsageFetcher: Sendable` with `public static let defaultArguments: [String]`, `public init(locate: @escaping @Sendable () -> Result<URL, UsageError> = ClaudeLocator.locate, arguments: [String] = UsageFetcher.defaultArguments, timeout: TimeInterval = 30, workingDirectory: URL = FileManager.default.temporaryDirectory)`, and `public func fetch() async -> Result<String, UsageError>`.

- [ ] **Step 1: Write the failing tests**

`Tests/UsageCoreTests/UsageFetcherTests.swift`:
```swift
import Foundation
import Testing
@testable import UsageCore

@Suite struct UsageFetcherTests {
    func fetcher(_ script: URL, timeout: TimeInterval = 5) -> UsageFetcher {
        UsageFetcher(locate: { .success(script) }, timeout: timeout)
    }

    @Test func returnsResultText() async throws {
        let script = try makeScript(#"printf '{"is_error":false,"result":"hello"}'"#)
        #expect(await fetcher(script).fetch() == .success("hello"))
    }

    @Test func passesUsageArguments() async throws {
        let script = try makeScript(#"printf '{"is_error":false,"result":"%s"}' "$*""#)
        #expect(await fetcher(script).fetch()
            == .success("-p /usage --no-session-persistence --output-format json"))
    }

    @Test func runsInWorkingDirectoryWithClaudeFirstOnPath() async throws {
        let script = try makeScript(#"printf '{"is_error":false,"result":"%s|%s"}' "$(basename "$(pwd)")" "${PATH%%:*}""#)
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let fetcher = UsageFetcher(locate: { .success(script) }, timeout: 5, workingDirectory: workDir)
        #expect(await fetcher.fetch()
            == .success("\(workDir.lastPathComponent)|\(script.deletingLastPathComponent().path)"))
    }

    @Test func claudeReportedError() async throws {
        let script = try makeScript(#"printf '{"is_error":true,"result":"Login expired"}'"#)
        #expect(await fetcher(script).fetch() == .failure(.claudeError(message: "Login expired")))
    }

    @Test func nonZeroExitUsesStderr() async throws {
        let script = try makeScript("echo 'boom' >&2\nexit 3")
        #expect(await fetcher(script).fetch() == .failure(.claudeError(message: "boom")))
    }

    @Test func nonZeroExitWithoutStderr() async throws {
        let script = try makeScript("exit 3")
        #expect(await fetcher(script).fetch()
            == .failure(.claudeError(message: "claude exited with status 3")))
    }

    @Test func nonJSONOutput() async throws {
        let script = try makeScript("echo 'not json'")
        #expect(await fetcher(script).fetch() == .failure(.unreadableOutput(sample: "not json")))
    }

    @Test func timesOut() async throws {
        let script = try makeScript("sleep 5")
        #expect(await fetcher(script, timeout: 0.5).fetch() == .failure(.timedOut))
    }

    @Test func missingExecutable() async {
        let missing = URL(fileURLWithPath: "/nonexistent/claude")
        #expect(await fetcher(missing).fetch() == .failure(.notFound(searched: ["/nonexistent/claude"])))
    }

    @Test func locateFailureIsPassedThrough() async {
        let fetcher = UsageFetcher(locate: { .failure(.notFound(searched: ["x"])) })
        #expect(await fetcher.fetch() == .failure(.notFound(searched: ["x"])))
    }

    /// Opt-in: runs the real `claude`. `CLAUDE_USAGE_E2E=1 ./test.sh --filter realClaudeEndToEnd`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDE_USAGE_E2E"] == "1"))
    func realClaudeEndToEnd() async throws {
        let text = try await UsageFetcher().fetch().get()
        let limits = UsageParser.parse(text)
        #expect(!limits.isEmpty, "Parsed no limits from: \(text.prefix(300))")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter UsageFetcherTests`
Expected: build FAILS with `cannot find 'UsageFetcher' in scope`.

- [ ] **Step 3: Implement the fetcher**

`Sources/UsageCore/UsageFetcher.swift`:
```swift
import Foundation

/// Runs `claude -p /usage` and returns the text Claude Code printed.
public struct UsageFetcher: Sendable {
    public static let defaultArguments = ["-p", "/usage", "--no-session-persistence", "--output-format", "json"]

    private let locate: @Sendable () -> Result<URL, UsageError>
    private let arguments: [String]
    private let timeout: TimeInterval
    private let workingDirectory: URL

    /// `workingDirectory` defaults to a neutral folder so no project's `.claude/` settings or hooks apply.
    public init(
        locate: @escaping @Sendable () -> Result<URL, UsageError> = ClaudeLocator.locate,
        arguments: [String] = UsageFetcher.defaultArguments,
        timeout: TimeInterval = 30,
        workingDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.locate = locate
        self.arguments = arguments
        self.timeout = timeout
        self.workingDirectory = workingDirectory
    }

    public func fetch() async -> Result<String, UsageError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: fetchBlocking())
            }
        }
    }

    private func fetchBlocking() -> Result<String, UsageError> {
        let executable: URL
        switch locate() {
        case .success(let url): executable = url
        case .failure(let error): return .failure(error)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")

        switch ProcessRunner.run(
            executable, arguments: arguments, workingDirectory: workingDirectory,
            environment: environment, timeout: timeout)
        {
        case .failure(.launchFailed): return .failure(.notFound(searched: [executable.path]))
        case .failure(.timedOut): return .failure(.timedOut)
        case .success(let output): return Self.interpret(output)
        }
    }

    static func interpret(_ output: ProcessOutput) -> Result<String, UsageError> {
        if let payload = try? JSONDecoder().decode(Payload.self, from: output.stdout) {
            return payload.isError ? .failure(.claudeError(message: payload.result)) : .success(payload.result)
        }
        if output.status != 0 {
            let stderr = String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.claudeError(message: stderr.isEmpty ? "claude exited with status \(output.status)" : stderr))
        }
        return .failure(.unreadableOutput(sample: UsageError.sample(of: String(decoding: output.stdout, as: UTF8.self))))
    }
}

private struct Payload: Decodable {
    let isError: Bool
    let result: String

    enum CodingKeys: String, CodingKey {
        case isError = "is_error"
        case result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh --filter UsageFetcherTests`
Expected: PASS, 10 tests; `realClaudeEndToEnd` reported as skipped.

- [ ] **Step 5: Run the end-to-end test against the real claude and check no transcript is left**

Run:
```bash
MARK=$(mktemp)
CLAUDE_USAGE_E2E=1 ./test.sh --filter realClaudeEndToEnd
find ~/.claude/projects -path '*folders*' -name '*.jsonl' -newer "$MARK"
```
Expected: the test PASSES, and `find` prints nothing (the `--no-session-persistence` flag works). If the test fails, the failure message shows the start of the real output: fix `UsageParser` to match it and add that output as a new parser test before continuing.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageCore/UsageFetcher.swift Tests/UsageCoreTests/UsageFetcherTests.swift
git commit -m "feat: add usage fetcher that runs claude -p /usage"
```

---

### Task 4: UsageStore

**Files:**
- Create: `Sources/UsageCore/UsageStore.swift`
- Test: `Tests/UsageCoreTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: `UsageParser.parse` (Task 1), `UsageError`, `UsageError.sample(of:)` (Task 2), `Fixtures.usageOutput`.
- Produces: `@MainActor @Observable public final class UsageStore` with `public private(set) var limits: [Limit]`, `lastSuccess: Date?`, `error: UsageError?`, `isRefreshing: Bool`; `public init(fetch: @escaping @Sendable () async -> Result<String, UsageError>)`; `public func refresh() async`; `public func startAutoRefresh(interval: Duration = .seconds(300))`; `public func stopAutoRefresh()`.

- [ ] **Step 1: Write the failing tests**

`Tests/UsageCoreTests/UsageStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import UsageCore

/// Hands out scripted results in order (repeating the last one) and counts calls.
actor ScriptedFetch {
    private var results: [Result<String, UsageError>]
    private let delay: Duration
    private(set) var calls = 0

    init(_ results: [Result<String, UsageError>], delay: Duration = .zero) {
        self.results = results
        self.delay = delay
    }

    func next() async -> Result<String, UsageError> {
        calls += 1
        if delay > .zero { try? await Task.sleep(for: delay) }
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

@MainActor
@Suite struct UsageStoreTests {
    func makeStore(_ fetch: ScriptedFetch) -> UsageStore {
        UsageStore(fetch: { await fetch.next() })
    }

    @Test func successStoresLimits() async {
        let store = makeStore(ScriptedFetch([.success(Fixtures.usageOutput)]))
        await store.refresh()
        #expect(store.limits.map(\.shortName) == ["Session", "Week", "Fable"])
        #expect(store.error == nil)
        #expect(store.lastSuccess != nil)
        #expect(store.isRefreshing == false)
    }

    @Test func errorKeepsPreviousLimits() async {
        let store = makeStore(ScriptedFetch([.success(Fixtures.usageOutput), .failure(.timedOut)]))
        await store.refresh()
        let firstSuccess = store.lastSuccess
        await store.refresh()
        #expect(store.limits.count == 3)
        #expect(store.error == .timedOut)
        #expect(store.lastSuccess == firstSuccess)
    }

    @Test func successClearsError() async {
        let store = makeStore(ScriptedFetch([.failure(.timedOut), .success(Fixtures.usageOutput)]))
        await store.refresh()
        #expect(store.error == .timedOut)
        await store.refresh()
        #expect(store.error == nil)
    }

    @Test func unparseableOutputIsAnError() async {
        let store = makeStore(ScriptedFetch([.success("Something completely different\nsecond line")]))
        await store.refresh()
        #expect(store.limits.isEmpty)
        #expect(store.error == .unparseable(sample: "Something completely different\nsecond line"))
        #expect(store.lastSuccess == nil)
    }

    @Test func concurrentRefreshFetchesOnce() async {
        let fetch = ScriptedFetch([.success(Fixtures.usageOutput)], delay: .milliseconds(100))
        let store = makeStore(fetch)
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)
        #expect(await fetch.calls == 1)
    }

    @Test func autoRefreshRepeats() async throws {
        let fetch = ScriptedFetch([.success(Fixtures.usageOutput)])
        let store = makeStore(fetch)
        store.startAutoRefresh(interval: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(300))
        store.stopAutoRefresh()
        #expect(await fetch.calls >= 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter UsageStoreTests`
Expected: build FAILS with `cannot find 'UsageStore' in scope`.

- [ ] **Step 3: Implement the store**

`Sources/UsageCore/UsageStore.swift`:
```swift
import Foundation
import Observation

/// The app's usage state. On failure it keeps the last good limits so the UI can show them as stale.
@MainActor
@Observable
public final class UsageStore {
    public private(set) var limits: [Limit] = []
    public private(set) var lastSuccess: Date?
    public private(set) var error: UsageError?
    public private(set) var isRefreshing = false

    private let fetch: @Sendable () async -> Result<String, UsageError>
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?

    public init(fetch: @escaping @Sendable () async -> Result<String, UsageError>) {
        self.fetch = fetch
    }

    /// Fetches and parses usage. Does nothing if a refresh is already running.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        switch await fetch() {
        case .success(let text):
            let parsed = UsageParser.parse(text)
            if parsed.isEmpty {
                error = .unparseable(sample: UsageError.sample(of: text))
            } else {
                limits = parsed
                lastSuccess = Date()
                error = nil
            }
        case .failure(let failure):
            error = failure
        }
    }

    /// Refreshes now and then every `interval`, until `stopAutoRefresh()`.
    public func startAutoRefresh(interval: Duration = .seconds(300)) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh --filter UsageStoreTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/UsageStore.swift Tests/UsageCoreTests/UsageStoreTests.swift
git commit -m "feat: add observable usage store with stale-data handling"
```

---

### Task 5: MenuBarLabel

**Files:**
- Create: `Sources/UsageCore/MenuBarLabel.swift`
- Test: `Tests/UsageCoreTests/MenuBarLabelTests.swift`

**Interfaces:**
- Consumes: `Limit`, `UsageParser.parse` (Task 1), `UsageError` (Task 2), `Fixtures.usageOutput`.
- Produces:
  - `public enum Level: Equatable, Sendable { case normal, warning, critical, stale }`
  - `public struct Segment: Equatable, Sendable { public let text: String; public let level: Level }` with `public init(text:level:)`
  - `public enum MenuBarLabel { public static func level(for percent: Double) -> Level; public static func percentText(_ percent: Double) -> String; public static func segments(limits: [Limit], error: UsageError?) -> [Segment]; public static func tooltip(limits: [Limit]) -> String }`

- [ ] **Step 1: Write the failing tests**

`Tests/UsageCoreTests/MenuBarLabelTests.swift`:
```swift
import Testing
@testable import UsageCore

@Suite struct MenuBarLabelTests {
    let limits = UsageParser.parse(Fixtures.usageOutput) // 42, 62, 93

    @Test(arguments: zip([0, 79.9, 80, 94.9, 95, 100], [Level.normal, .normal, .warning, .warning, .critical, .critical]))
    func thresholds(percent: Double, expected: Level) {
        #expect(MenuBarLabel.level(for: percent) == expected)
    }

    @Test func percentTextRoundsDown() {
        #expect(MenuBarLabel.percentText(42) == "42%")
        #expect(MenuBarLabel.percentText(79.9) == "79%")
    }

    @Test func normalState() {
        let segments = MenuBarLabel.segments(limits: limits, error: nil)
        #expect(segments.map(\.text).joined() == "42% · 62% · 93%")
        #expect(segments.filter { $0.text.hasSuffix("%") }.map(\.level) == [.normal, .normal, .warning])
    }

    @Test func loadingState() {
        #expect(MenuBarLabel.segments(limits: [], error: nil) == [Segment(text: "\u{2013}", level: .normal)])
    }

    @Test func errorWithoutData() {
        #expect(MenuBarLabel.segments(limits: [], error: .timedOut)
            == [Segment(text: "\u{26A0}\u{FE0E}", level: .normal)])
    }

    @Test func errorWithStaleData() {
        let segments = MenuBarLabel.segments(limits: limits, error: .timedOut)
        #expect(segments.map(\.text).joined() == "\u{26A0}\u{FE0E} 42% · 62% · 93%")
        #expect(segments.allSatisfy { $0.level == .stale })
    }

    @Test func tooltip() {
        #expect(MenuBarLabel.tooltip(limits: limits) == "Session 42% · Week 62% · Fable 93%")
        #expect(MenuBarLabel.tooltip(limits: []) == "Claude usage")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./test.sh --filter MenuBarLabelTests`
Expected: build FAILS with `cannot find 'MenuBarLabel' in scope`.

- [ ] **Step 3: Implement MenuBarLabel**

`Sources/UsageCore/MenuBarLabel.swift`:
```swift
/// How a percentage should be coloured.
public enum Level: Equatable, Sendable {
    case normal, warning, critical, stale
}

/// A run of menu bar text in one colour.
public struct Segment: Equatable, Sendable {
    public let text: String
    public let level: Level

    public init(text: String, level: Level) {
        self.text = text
        self.level = level
    }
}

/// What the menu bar shows, independent of AppKit so it can be tested.
public enum MenuBarLabel {
    static let separator = " · "
    static let loading = "\u{2013}"
    static let warningSign = "\u{26A0}\u{FE0E}"

    public static func level(for percent: Double) -> Level {
        if percent >= 95 { return .critical }
        if percent >= 80 { return .warning }
        return .normal
    }

    /// Rounded down, so the shown number never crosses a threshold before the colour does.
    public static func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded(.down)))%"
    }

    /// `42% · 62% · 93%`; `–` before the first result; `⚠︎` on error, followed by the
    /// previous numbers greyed out if there are any.
    public static func segments(limits: [Limit], error: UsageError?) -> [Segment] {
        guard !limits.isEmpty else {
            return [Segment(text: error == nil ? loading : warningSign, level: .normal)]
        }
        let stale = error != nil
        var result = stale ? [Segment(text: warningSign + " ", level: .stale)] : []
        for (index, limit) in limits.enumerated() {
            if index > 0 { result.append(Segment(text: separator, level: stale ? .stale : .normal)) }
            result.append(Segment(
                text: percentText(limit.percent),
                level: stale ? .stale : level(for: limit.percent)))
        }
        return result
    }

    public static func tooltip(limits: [Limit]) -> String {
        guard !limits.isEmpty else { return "Claude usage" }
        return limits.map { "\($0.shortName) \(percentText($0.percent))" }.joined(separator: separator)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./test.sh`
Expected: PASS, the whole suite (MenuBarLabel adds 12 test cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageCore/MenuBarLabel.swift Tests/UsageCoreTests/MenuBarLabelTests.swift
git commit -m "feat: add menu bar label logic with thresholds and stale state"
```

---

### Task 6: App shell, status item and build script

**Files:**
- Modify: `Package.swift` (add the executable target)
- Create: `Sources/ClaudeUsage/ClaudeUsageMain.swift`, `Sources/ClaudeUsage/AppDelegate.swift`, `Sources/ClaudeUsage/StatusItemController.swift`, `Sources/ClaudeUsage/LevelColors.swift`, `Resources/Info.plist`, `build.sh`, `README.md`

**Interfaces:**
- Consumes: `UsageStore`, `UsageFetcher`, `MenuBarLabel`, `Level`, `Segment` (Tasks 3–5).
- Produces: `StatusItemController(store: UsageStore)`; `extension Level { var nsColor: NSColor }`; `build/Claude Usage.app` via `./build.sh`, installed via `./build.sh install`.

- [ ] **Step 1: Add the executable target**

Replace `Package.swift` with:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "ClaudeUsage", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
```

- [ ] **Step 2: Write the app entry point and delegate**

`Sources/ClaudeUsage/ClaudeUsageMain.swift`:
```swift
import AppKit

@main
@MainActor
enum ClaudeUsageMain {
    static func main() {
        let app = NSApplication.shared
        // Info.plist's LSUIElement does this for the bundled app; this also covers running the bare binary.
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
```

`Sources/ClaudeUsage/AppDelegate.swift`:
```swift
import AppKit
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusItemController: StatusItemController?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore(fetch: { await UsageFetcher().fetch() })
        self.store = store
        statusItemController = StatusItemController(store: store)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await store.refresh() }
        }
        store.startAutoRefresh()
    }
}
```

- [ ] **Step 3: Write the status item controller and colours**

`Sources/ClaudeUsage/LevelColors.swift`:
```swift
import AppKit
import UsageCore

extension Level {
    var nsColor: NSColor {
        switch self {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        case .stale: .secondaryLabelColor
        }
    }
}
```

`Sources/ClaudeUsage/StatusItemController.swift`:
```swift
import AppKit
import Observation
import UsageCore

/// Owns the menu bar item. Uses NSStatusItem rather than SwiftUI's MenuBarExtra because
/// MenuBarExtra draws its label in a single colour.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem

    init(store: UsageStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        observeStore()
    }

    /// Re-renders whenever the store's limits or error change.
    private func observeStore() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func render() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let title = NSMutableAttributedString()
        for segment in MenuBarLabel.segments(limits: store.limits, error: store.error) {
            title.append(NSAttributedString(
                string: segment.text,
                attributes: [.font: font, .foregroundColor: segment.level.nsColor]))
        }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = MenuBarLabel.tooltip(limits: store.limits)
    }
}
```

- [ ] **Step 4: Write Info.plist, build script and README**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.roald.ClaudeUsage</string>
    <key>CFBundleName</key>
    <string>Claude Usage</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

`build.sh`:
```bash
#!/bin/bash
# Builds "Claude Usage.app" into build/. With `install`, also copies it to /Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="build/Claude Usage.app"

swift build -c release --product ClaudeUsage
BIN="$(swift build -c release --show-bin-path)/ClaudeUsage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x ClaudeUsage || true
    rm -rf "/Applications/Claude Usage.app"
    cp -R "$APP" /Applications/
    open "/Applications/Claude Usage.app"
    echo "Installed to /Applications and launched"
fi
```
Run: `chmod +x build.sh`

`README.md`:
````markdown
# Claude Usage

A macOS menu bar app that shows your Claude subscription usage limits (current session, current
week, and per-model week) as `42% · 62% · 93%`. It gets the numbers by running Claude Code's own
`claude -p "/usage"`, so it needs no API token.

Requirements: macOS 14+, Xcode (only its toolchain is used), and Claude Code installed and logged in.

```bash
./build.sh install   # build, copy to /Applications, launch
./build.sh           # build only → build/Claude Usage.app
./test.sh            # run the tests
CLAUDE_USAGE_E2E=1 ./test.sh --filter realClaudeEndToEnd   # check against the real claude
```

Design: `docs/superpowers/specs/2026-09-11-claude-usage-menubar-design.md`
````

- [ ] **Step 5: Build and confirm tests still pass**

Run: `./build.sh && ./test.sh`
Expected: `Built build/Claude Usage.app`; all tests PASS. Fix any Swift 6 concurrency errors properly (no `@preconcurrency`/`nonisolated(unsafe)` escapes) before continuing.

- [ ] **Step 6: Launch and check the menu bar (manual — the controller asks the user)**

Run: `open "build/Claude Usage.app" && sleep 3 && pgrep -x ClaudeUsage`
Expected: a PID is printed. Ask the user to confirm: the menu bar shows `–` briefly, then something like `42% · 62% · 93%` with any value ≥ 80 in orange; hovering shows `Session 42% · Week 62% · Fable 93%`; there is no Dock icon. Then quit it: `pkill -x ClaudeUsage`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ClaudeUsage Resources build.sh README.md
git commit -m "feat: add menu bar app shell and build script"
```

---

### Task 7: Dropdown popover

**Files:**
- Create: `Sources/ClaudeUsage/DropdownView.swift`
- Modify: `Sources/ClaudeUsage/StatusItemController.swift` (add popover), `Sources/ClaudeUsage/LevelColors.swift` (add `barColor`)

**Interfaces:**
- Consumes: `UsageStore` (`limits`, `error`, `lastSuccess`, `isRefreshing`, `refresh()`), `Limit`, `UsageError.message/detail`, `MenuBarLabel.level(for:)`, `MenuBarLabel.percentText(_:)`, `Level`.
- Produces: `struct DropdownView: View` with `init(store: UsageStore)`; `extension Level { var barColor: Color }`.

- [ ] **Step 1: Add bar colours**

Replace `Sources/ClaudeUsage/LevelColors.swift` with:
```swift
import AppKit
import SwiftUI
import UsageCore

extension Level {
    var nsColor: NSColor {
        switch self {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        case .stale: .secondaryLabelColor
        }
    }

    /// Progress bars use the accent colour when normal; the menu bar uses the plain text colour.
    var barColor: Color {
        self == .normal ? .accentColor : Color(nsColor: nsColor)
    }
}
```

- [ ] **Step 2: Write the dropdown view**

`Sources/ClaudeUsage/DropdownView.swift`:
```swift
import AppKit
import SwiftUI
import UsageCore

struct DropdownView: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.error {
                ErrorBanner(error: error)
            }
            if store.limits.isEmpty && store.error == nil {
                Text("Loading usage…").foregroundStyle(.secondary)
            }
            ForEach(store.limits, id: \.label) { limit in
                LimitRow(limit: limit, stale: store.error != nil)
            }
            Divider()
            HStack {
                TimelineView(.everyMinute) { context in
                    Text(footerText(now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh now")
                }
            }
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func footerText(now: Date) -> String {
        guard let lastSuccess = store.lastSuccess else { return "Not updated yet" }
        let relative = lastSuccess.formatted(
            .relative(presentation: .named).locale(Locale(identifier: "en_US")))
        return (store.error == nil ? "Updated " : "Last updated ") + relative
    }
}

private struct LimitRow: View {
    let limit: Limit
    let stale: Bool

    var body: some View {
        let level: Level = stale ? .stale : MenuBarLabel.level(for: limit.percent)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label).font(.callout.weight(.medium))
                Spacer()
                Text(MenuBarLabel.percentText(limit.percent)).monospacedDigit()
            }
            ProgressView(value: min(max(limit.percent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(level.barColor)
            Text(limit.resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(stale ? .secondary : .primary)
    }
}

private struct ErrorBanner: View {
    let error: UsageError

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            if let detail = error.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
    }
}
```

- [ ] **Step 3: Add the popover to the status item controller**

Replace `Sources/ClaudeUsage/StatusItemController.swift` with:
```swift
import AppKit
import Observation
import SwiftUI
import UsageCore

/// Owns the menu bar item and its popover. Uses NSStatusItem rather than SwiftUI's MenuBarExtra
/// because MenuBarExtra draws its label in a single colour.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(store: UsageStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let hosting = NSHostingController(rootView: DropdownView(store: store))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        observeStore()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate()
            Task { await store.refresh() }
        }
    }

    /// Re-renders whenever the store's limits or error change.
    private func observeStore() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func render() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let title = NSMutableAttributedString()
        for segment in MenuBarLabel.segments(limits: store.limits, error: store.error) {
            title.append(NSAttributedString(
                string: segment.text,
                attributes: [.font: font, .foregroundColor: segment.level.nsColor]))
        }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = MenuBarLabel.tooltip(limits: store.limits)
    }
}
```

- [ ] **Step 4: Build and confirm tests still pass**

Run: `./build.sh && ./test.sh`
Expected: `Built build/Claude Usage.app`; all tests PASS.

- [ ] **Step 5: Check the dropdown (manual — the controller asks the user)**

Run: `open "build/Claude Usage.app"`
Ask the user to confirm: clicking the menu bar item opens the dropdown with three rows (label, percentage, coloured bar, reset text without `(Europe/Amsterdam)`); the footer reads `Updated … ago`; ↻ shows a spinner briefly and refreshes; clicking elsewhere closes the dropdown; Quit quits the app.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeUsage
git commit -m "feat: add usage dropdown popover"
```

---

### Task 8: Open at login

**Files:**
- Create: `Sources/ClaudeUsage/LoginItem.swift`
- Modify: `Sources/ClaudeUsage/DropdownView.swift`, `Sources/ClaudeUsage/StatusItemController.swift`, `Sources/ClaudeUsage/AppDelegate.swift`

**Interfaces:**
- Consumes: `StatusItemController` and `DropdownView` from Task 7.
- Produces: `@MainActor @Observable final class LoginItem` with `private(set) var isEnabled: Bool`, `private(set) var problem: String?`, `func setEnabled(_ enabled: Bool)`, `func enableOnFirstLaunch(defaults: UserDefaults = .standard)`. `DropdownView(store:loginItem:)`, `StatusItemController(store:loginItem:)`.

- [ ] **Step 1: Write LoginItem (SMAppService version)**

`Sources/ClaudeUsage/LoginItem.swift`:
```swift
import Foundation
import Observation
import ServiceManagement

/// The "Open at login" setting, backed by the system login items list.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var problem: String?

    init() {
        refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        problem = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            problem = error.localizedDescription
        }
        refreshStatus()
    }

    /// Turns the setting on the first time the app runs; afterwards the user's choice stands.
    func enableOnFirstLaunch(defaults: UserDefaults = .standard) {
        let key = "hasConfiguredLoginItem"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        setEnabled(true)
    }

    private func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        if status == .requiresApproval {
            problem = "Approve Claude Usage in System Settings → General → Login Items"
        }
    }
}
```

- [ ] **Step 2: Add the toggle to the dropdown**

In `Sources/ClaudeUsage/DropdownView.swift`, change the stored properties of `DropdownView` from:
```swift
    let store: UsageStore
```
to:
```swift
    let store: UsageStore
    let loginItem: LoginItem
```
and insert this directly above `Button("Quit") { NSApp.terminate(nil) }`:
```swift
            Toggle("Open at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }))
                .toggleStyle(.checkbox)
            if let problem = loginItem.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 3: Pass the login item through**

In `Sources/ClaudeUsage/StatusItemController.swift`, change:
```swift
    init(store: UsageStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let hosting = NSHostingController(rootView: DropdownView(store: store))
```
to:
```swift
    init(store: UsageStore, loginItem: LoginItem) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let hosting = NSHostingController(rootView: DropdownView(store: store, loginItem: loginItem))
```

In `Sources/ClaudeUsage/AppDelegate.swift`, add a property below `private var wakeObserver: NSObjectProtocol?`:
```swift
    private var loginItem: LoginItem?
```
and replace:
```swift
        statusItemController = StatusItemController(store: store)
```
with:
```swift
        let loginItem = LoginItem()
        self.loginItem = loginItem
        loginItem.enableOnFirstLaunch()
        statusItemController = StatusItemController(store: store, loginItem: loginItem)
```

- [ ] **Step 4: Build, install and test the toggle (manual — the controller asks the user)**

Run: `./build.sh install && ./test.sh`
Expected: installed and launched; all tests PASS. Ask the user to open the dropdown and confirm:
1. "Open at login" is checked with no message under it.
2. System Settings → General → Login Items lists "Claude Usage".
3. Unchecking removes it from that list; checking adds it back.

If a message appears under the toggle, or the app never shows up in Login Items, do Step 5. Otherwise skip Step 5.

- [ ] **Step 5 (only if Step 4 failed): Switch to a LaunchAgent**

Replace `Sources/ClaudeUsage/LoginItem.swift` with this version, which has the same interface:
```swift
import Foundation
import Observation

/// The "Open at login" setting, backed by a LaunchAgent (SMAppService rejected the ad-hoc-signed app).
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var problem: String?

    private let plistURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/local.roald.ClaudeUsage.plist")

    init() {
        isEnabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        problem = nil
        do {
            if enabled {
                let plist: [String: Any] = [
                    "Label": "local.roald.ClaudeUsage",
                    "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                    "RunAtLoad": true,
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try FileManager.default.createDirectory(
                    at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: plistURL)
            } else if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
        } catch {
            problem = error.localizedDescription
        }
        isEnabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Turns the setting on the first time the app runs; afterwards the user's choice stands.
    func enableOnFirstLaunch(defaults: UserDefaults = .standard) {
        let key = "hasConfiguredLoginItem"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        setEnabled(true)
    }
}
```
Then run `defaults delete local.roald.ClaudeUsage hasConfiguredLoginItem; ./build.sh install`, and check: `plutil -p ~/Library/LaunchAgents/local.roald.ClaudeUsage.plist` shows `RunAtLoad => true` and a `ProgramArguments` ending in `/Applications/Claude Usage.app`; unchecking the toggle deletes the file. Update the "Open at login" bullet in the spec to say a LaunchAgent is used and why.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeUsage docs/superpowers/specs
git commit -m "feat: add open-at-login toggle"
```

---

### Task 9: End-to-end check

**Files:** none (verification only; fixes go in the file that's wrong, with a test where the bug is in `UsageCore`).

- [ ] **Step 1: Full test run, including the real claude**

Run: `./test.sh && CLAUDE_USAGE_E2E=1 ./test.sh --filter realClaudeEndToEnd`
Expected: all PASS.

- [ ] **Step 2: Walk through the installed app (manual — the controller asks the user)**

With `/Applications/Claude Usage.app` running, ask the user to confirm:
1. The menu bar numbers match `claude -p "/usage" --no-session-persistence` run in a terminal.
2. Colours: numbers ≥ 80 are orange, ≥ 95 red, others the normal menu bar colour, in both light and dark mode.
3. The dropdown matches the spec mockup; the reset texts have no timezone suffix.
4. After the Mac sleeps and wakes, the footer shows a fresh "Updated" time within a few seconds.
5. Error state: temporarily rename the real claude (`mv ~/.local/bin/claude ~/.local/bin/claude.off`), click ↻, and confirm `⚠︎` plus greyed-out old numbers in the menu bar, and "Couldn't find the claude command" with the searched locations in the dropdown. Restore it with `mv ~/.local/bin/claude.off ~/.local/bin/claude` and click ↻ again: the normal display returns.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: issues found in end-to-end check"
```
(Skip if nothing changed.)
