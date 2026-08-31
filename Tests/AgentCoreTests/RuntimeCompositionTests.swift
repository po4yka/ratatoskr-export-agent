import AgentCore
import XCTest

final class RuntimeCompositionTests: XCTestCase {
  func testNormalLaunchStartsOneSharedOperationalRuntime() async {
    let components = (0..<5).map { _ in RuntimeComponentRecorder() }
    let runtime = OperationalAgentRuntime(components: components)

    await runtime.start()
    await runtime.start()

    for component in components {
      let counts = await component.counts
      XCTAssertEqual(counts.starts, 1)
      XCTAssertEqual(counts.reconciles, 1)
    }
  }

  func testShutdownWakeAndNetworkRecoveryCoalesceWithoutDuplicateWork() async {
    let component = RuntimeComponentRecorder()
    let runtime = OperationalAgentRuntime(components: [component])
    await runtime.start()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<10 { group.addTask { await runtime.reconcile() } }
    }
    await runtime.stop()
    await runtime.stop()

    let counts = await component.counts
    XCTAssertEqual(counts.starts, 1)
    XCTAssertLessThanOrEqual(counts.reconciles, 3)
    XCTAssertEqual(counts.stops, 1)
  }

  func testShutdownWaitsForInFlightReconciliationBeforeStoppingComponents() async {
    let component = ShutdownOrderingRecorder()
    let runtime = OperationalAgentRuntime(components: [component])
    await runtime.start()
    await component.blockNextReconciliation()
    let reconciliation = Task { await runtime.reconcile() }
    await component.waitUntilBlocked()

    let shutdown = Task { await runtime.stop() }
    for _ in 0..<10 { await Task.yield() }
    await component.releaseReconciliation()
    await reconciliation.value
    await shutdown.value

    let overlapped = await component.stopOverlappedReconciliation
    XCTAssertFalse(overlapped)
  }

  func testInboxRuntimeReconciliationRunsANewFolderScan() async {
    let scenario = WatchScenario()
    let passes = PassCounter()
    let target = WatchedFolderTarget(
      id: UUID(), url: WatchScenario.folderURL(named: "wake-reconcile"), isEnabled: true
    )
    let watcher = scenario.makeCoordinator(targets: [target]) { passes.bump() }
    let component = InboxRuntimeComponent(watcher: watcher)

    await component.start()
    XCTAssertEqual(passes.value, 1)
    await component.reconcile()

    XCTAssertEqual(passes.value, 2)
    await component.stop()
  }
}

private actor RuntimeComponentRecorder: OperationalRuntimeComponent {
  private var starts = 0
  private var reconciles = 0
  private var stops = 0

  var counts: (starts: Int, reconciles: Int, stops: Int) { (starts, reconciles, stops) }
  func start() async { starts += 1 }
  func reconcile() async {
    reconciles += 1
    try? await Task.sleep(for: .milliseconds(10))
  }
  func stop() async { stops += 1 }
}

private actor ShutdownOrderingRecorder: OperationalRuntimeComponent {
  private var shouldBlock = false
  private var isReconciling = false
  private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var stopOverlappedReconciliation = false

  func start() async {}
  func blockNextReconciliation() { shouldBlock = true }
  func reconcile() async {
    guard shouldBlock else { return }
    shouldBlock = false
    isReconciling = true
    blockedWaiters.forEach { $0.resume() }
    blockedWaiters.removeAll()
    await withCheckedContinuation { releaseWaiters.append($0) }
    isReconciling = false
  }
  func stop() async { stopOverlappedReconciliation = isReconciling }

  func waitUntilBlocked() async {
    guard !isReconciling else { return }
    await withCheckedContinuation { blockedWaiters.append($0) }
  }

  func releaseReconciliation() {
    releaseWaiters.forEach { $0.resume() }
    releaseWaiters.removeAll()
  }
}
