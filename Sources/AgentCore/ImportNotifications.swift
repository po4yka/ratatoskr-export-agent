import Foundation

/// Generic terminal notice. It deliberately has no provider, archive, path, count, or diagnostic.
extension AgentNotification {
  public init(presentation: BackendImportPresentation) {
    switch presentation {
    case .importedComplete:
      title = "Archive import complete"
      body = "Your archive import has completed."
    case .importedWithGaps, .unverified:
      title = "Archive import needs attention"
      body = "Your archive import completed with information to review."
    case .failed:
      title = "Archive import failed"
      body = "Your archive import could not be completed."
    case .archived, .uploading, .processing:
      title = ""
      body = ""
    }
  }
}

/// Delivers a terminal import notice once, and records delivery only after the system accepts it.
public final class ImportNotificationCoordinator: @unchecked Sendable {
  private let journal: LocalArchiveJournal
  private let service: any AgentNotificationServing
  private let inFlightLock = NSLock()
  private var inFlightEntries: Set<UUID> = []

  public init(journal: LocalArchiveJournal, service: any AgentNotificationServing) {
    self.journal = journal
    self.service = service
  }

  @discardableResult
  public func notifyIfNeeded(entryID: UUID) async -> Bool {
    guard let entry = journal.entries.first(where: { $0.id == entryID }),
          let observation = entry.backendImport,
          observation.presentation.isTerminal,
          !observation.terminalNoticeDelivered,
          await service.authorization() == .authorized
    else { return false }
    guard reserve(entryID) else { return false }
    defer { release(entryID) }
    guard let current = journal.entries.first(where: { $0.id == entryID }),
          let currentObservation = current.backendImport,
          currentObservation.presentation.isTerminal,
          !currentObservation.terminalNoticeDelivered
    else { return false }
    do {
      try await service.deliver(AgentNotification(presentation: currentObservation.presentation))
      _ = try journal.markBackendTerminalNoticeDelivered(
        entryID: entryID, operationID: currentObservation.operationID
      )
      return true
    } catch {
      return false
    }
  }

  private func reserve(_ entryID: UUID) -> Bool {
    inFlightLock.lock()
    defer { inFlightLock.unlock() }
    return inFlightEntries.insert(entryID).inserted
  }

  private func release(_ entryID: UUID) {
    inFlightLock.lock()
    inFlightEntries.remove(entryID)
    inFlightLock.unlock()
  }
}

#if canImport(UserNotifications)
import UserNotifications

/// macOS adapter: reads the existing permission decision and never requests permission itself.
public actor UserAgentNotificationService: AgentNotificationServing {
  private let center: UNUserNotificationCenter

  public init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  public func authorization() async -> ImportNotificationAuthorization {
    await withCheckedContinuation { continuation in
      center.getNotificationSettings { settings in
        continuation.resume(returning: settings.authorizationStatus == .authorized ? .authorized : .deniedOrUnavailable)
      }
    }
  }

  public func deliver(_ notice: AgentNotification) async throws {
    let content = UNMutableNotificationContent()
    content.title = notice.title
    content.body = notice.body
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    let _: Void = try await withCheckedThrowingContinuation { continuation in
      center.add(request) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }
}
#endif
