import Foundation

extension UploadQueue {
  func publishStatus() {
    publish(UploadQueueStatus(entries: journal.entries))
  }

  func publish(_ status: UploadQueueStatus) {
    for continuation in statusContinuations.values {
      continuation.yield(status)
    }
  }

  func removeStatusContinuation(_ id: UUID) {
    statusContinuations[id] = nil
  }
}
