import AgentCore
import XCTest

final class ObsidianCLIRenameCheckTests: XCTestCase {
  func testListWithNewPathOnlyConfirms() {
    let runner = ScriptedCLIRunner(answer: ObsidianCLIAnswer(status: 0, output: "B.md\nNotes/C.md\n"))
    let check = ObsidianCLIRenameCheck(vaultName: "Fixture", runner: runner)

    XCTAssertEqual(check.verdict(renaming: "A.md", to: "B.md"), .confirmed)
    XCTAssertEqual(runner.calls, [["vault=Fixture", "files"]])
  }

  func testListWithBothPathsRefutes() {
    let runner = ScriptedCLIRunner(answer: ObsidianCLIAnswer(status: 0, output: "A.md\nB.md\n"))
    let check = ObsidianCLIRenameCheck(vaultName: "Fixture", runner: runner)

    XCTAssertEqual(check.verdict(renaming: "A.md", to: "B.md"), .refuted)
  }

  func testNFDListMatchesNFCPath() {
    let runner = ScriptedCLIRunner(answer: ObsidianCLIAnswer(status: 0, output: "Cafe\u{0301}.md\n"))
    let check = ObsidianCLIRenameCheck(vaultName: "Fixture", runner: runner)

    XCTAssertEqual(check.verdict(renaming: "A.md", to: "Caf\u{00E9}.md"), .confirmed)
  }

  func testUnclearAnswersAreUnavailable() {
    let failing = ObsidianCLIRenameCheck(vaultName: "V", runner: ScriptedCLIRunner(answer: ObsidianCLIAnswer(status: 1, output: "B.md")))
    let unknownFormat = ObsidianCLIRenameCheck(vaultName: "V", runner: ScriptedCLIRunner(answer: ObsidianCLIAnswer(status: 0, output: "- B.md")))

    XCTAssertEqual(failing.verdict(renaming: "A.md", to: "B.md"), .unavailable)
    XCTAssertEqual(unknownFormat.verdict(renaming: "A.md", to: "B.md"), .unavailable)
  }

  func testNoAnswerIsUnavailableAndQuietForAPeriod() {
    let runner = ScriptedCLIRunner(answer: nil)
    let clock = CheckClock()
    let check = ObsidianCLIRenameCheck(vaultName: "V", runner: runner, quietPeriod: 60, now: { clock.now })

    XCTAssertEqual(check.verdict(renaming: "A.md", to: "B.md"), .unavailable)
    XCTAssertEqual(check.verdict(renaming: "C.md", to: "D.md"), .unavailable)
    XCTAssertEqual(runner.calls.count, 1, "a closed app is not asked again inside the quiet period")
    clock.now = clock.now.addingTimeInterval(61)
    _ = check.verdict(renaming: "C.md", to: "D.md")
    XCTAssertEqual(runner.calls.count, 2)
  }

  func testMissingExecutableIsUnavailable() {
    let runner = ProcessObsidianCLIRunner(candidates: ["/nonexistent-\(UUID().uuidString)/obsidian"])
    let check = ObsidianCLIRenameCheck(vaultName: "V", runner: runner)

    XCTAssertNil(runner.executable)
    XCTAssertEqual(check.verdict(renaming: "A.md", to: "B.md"), .unavailable)
  }

  func testRunnerStopsAProcessThatDoesNotEnd() {
    let runner = ProcessObsidianCLIRunner(candidates: ["/bin/sleep"], timeLimit: 0.2)

    XCTAssertNil(runner.run(["5"]), "a process that passes the time limit gives no answer")
  }

  func testRunnerReturnsStatusAndOutput() {
    let runner = ProcessObsidianCLIRunner(candidates: ["/bin/echo"])

    XCTAssertEqual(runner.run(["B.md"]), ObsidianCLIAnswer(status: 0, output: "B.md\n"))
  }
}

private final class ScriptedCLIRunner: ObsidianCLIRunning, @unchecked Sendable {
  private let answer: ObsidianCLIAnswer?
  private(set) var calls: [[String]] = []

  init(answer: ObsidianCLIAnswer?) {
    self.answer = answer
  }

  func run(_ arguments: [String]) -> ObsidianCLIAnswer? {
    calls.append(arguments)
    return answer
  }
}

private final class CheckClock: @unchecked Sendable {
  var now = Date(timeIntervalSinceReferenceDate: 5_000_000)
}
