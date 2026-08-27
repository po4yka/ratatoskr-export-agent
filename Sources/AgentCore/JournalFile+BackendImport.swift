import Foundation

extension JournalFile {
  static func isValidBackendObservationTransition(
    from previous: BackendImportObservation?, to next: BackendImportObservation?
  ) -> Bool {
    guard let next else { return false }
    guard let previous else { return next.presentation == .processing && next.observedAt == .distantPast }
    guard previous.operationID == next.operationID else { return false }
    guard next.observedAt >= previous.observedAt else { return false }
    guard !previous.presentation.isTerminal || next.presentation == previous.presentation else {
      return false
    }
    if let previousUpdatedAt = previous.backendUpdatedAt,
       let nextUpdatedAt = next.backendUpdatedAt,
       nextUpdatedAt < previousUpdatedAt {
      return false
    }
    return !previous.terminalNoticeDelivered || next.terminalNoticeDelivered
  }
}
