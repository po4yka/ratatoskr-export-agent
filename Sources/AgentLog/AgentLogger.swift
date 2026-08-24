public struct AgentLogger {
  private let sink: (String) -> Void
  private let verbose: Bool

  public init(sink: @escaping (String) -> Void, verbose: Bool = false) {
    self.sink = sink
    self.verbose = verbose
  }

  public func debug(_ message: String) {
    emit(message)
  }

  public func info(_ message: String) {
    emit(message)
  }

  private func emit(_ message: String) {
    sink(verbose ? message : LogRedactor.redact(message))
  }
}
