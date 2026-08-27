import Foundation

/// Reads an authenticated Platform operation without interpreting its private diagnostics.
public protocol BackendOperationPolling {
  func fetchOperation(_ operationID: UUID) async throws -> Data
}

/// Applies successful Platform operation reads to the one durable local journal.
///
/// A failed or malformed read deliberately performs no journal mutation: callers continue to see
/// the last successful observation and its timestamp rather than an invented replacement state.
public final class BackendImportPollCoordinator {
  private let journal: LocalArchiveJournal
  private let polling: any BackendOperationPolling

  public init(journal: LocalArchiveJournal, polling: any BackendOperationPolling) {
    self.journal = journal
    self.polling = polling
  }

  /// Refreshes one archive's known operation, retaining durable truth when Platform is unavailable.
  @discardableResult
  public func refresh(entryID: UUID, observedAt: Date = Date()) async -> JournalEntry? {
    guard let entry = journal.entries.first(where: { $0.id == entryID }),
          let known = entry.backendImport else {
      return nil
    }
    do {
      let data = try await polling.fetchOperation(known.operationID)
      let fact = try BackendImportStatusMapper.fact(from: data)
      if known.presentation.isTerminal, fact.presentation != known.presentation {
        return entry
      }
      if known.backendUpdatedAt != nil, fact.backendUpdatedAt == nil {
        return entry
      }
      if let previous = known.backendUpdatedAt, let incoming = fact.backendUpdatedAt, incoming < previous {
        return entry
      }
      return try journal.recordBackendObservation(
        entryID: entryID, operationID: known.operationID,
        presentation: fact.presentation, observedAt: observedAt, backendUpdatedAt: fact.backendUpdatedAt
      )
    } catch {
      return journal.entries.first(where: { $0.id == entryID })
    }
  }
}

/// Strict HTTPS reader for `GET /v1/operations/{id}` with a paired-device access credential.
public struct URLSessionBackendOperationPoller: BackendOperationPolling {
  private let origin: URL
  private let accessCredential: String
  private let session: URLSession

  public init(origin: URL, accessCredential: String) {
    self.origin = origin
    self.accessCredential = accessCredential
    let blocker = PlatformRedirectBlocker()
    session = URLSession(configuration: .ephemeral, delegate: blocker, delegateQueue: nil)
  }

  init(origin: URL, accessCredential: String, session: URLSession) {
    self.origin = origin
    self.accessCredential = accessCredential
    self.session = session
  }

  public func fetchOperation(_ operationID: UUID) async throws -> Data {
    guard let endpoint = URLSessionPlatformDeviceTransport.endpoint(
      for: origin, path: "v1/operations/\(operationID.uuidString.lowercased())"
    ) else {
      throw PlatformDeviceTransportError.invalidOrigin
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessCredential)", forHTTPHeaderField: "Authorization")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw PlatformDeviceTransportError.unavailable
    }
    guard let http = response as? HTTPURLResponse else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    guard http.statusCode == 200 else {
      throw http.statusCode == 401 ? PlatformDeviceTransportError.refused : PlatformDeviceTransportError.unavailable
    }
    return data
  }
}
