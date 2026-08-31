import Foundation

public protocol OperationalRuntimeComponent: Sendable {
  func start() async
  func reconcile() async
  func stop() async
}

/// Owns the long-lived product graph and serializes every lifecycle reconciliation.
public actor OperationalAgentRuntime {
  private let components: [any OperationalRuntimeComponent]
  private var isRunning = false
  private var isReconciling = false
  private var reconciliationPending = false
  private var isStopping = false
  private var stopWaiters: [CheckedContinuation<Void, Never>] = []

  public init(components: [any OperationalRuntimeComponent]) {
    self.components = components
  }

  public func start() async {
    guard !isRunning else { return }
    isRunning = true
    isReconciling = true
    for component in components where isRunning { await component.start() }
    if isRunning { await performReconciliationPasses() }
    isReconciling = false
    if isStopping { await finishStop() }
  }

  public func reconcile() async {
    guard isRunning else { return }
    if isReconciling {
      reconciliationPending = true
      return
    }
    isReconciling = true
    await performReconciliationPasses()
    isReconciling = false
    if isStopping { await finishStop() }
  }

  public func stop() async {
    guard isRunning || isReconciling || isStopping else { return }
    if isStopping {
      await withCheckedContinuation { stopWaiters.append($0) }
      return
    }
    isRunning = false
    reconciliationPending = false
    isStopping = true
    if isReconciling {
      await withCheckedContinuation { stopWaiters.append($0) }
      return
    }
    await finishStop()
  }

  private func performReconciliationPasses() async {
    repeat {
      reconciliationPending = false
      for component in components where isRunning { await component.reconcile() }
    } while isRunning && reconciliationPending
  }

  private func finishStop() async {
    for component in components.reversed() { await component.stop() }
    isStopping = false
    let waiters = stopWaiters
    stopWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}
