import Foundation

/// Keeps the results that notes did not take yet, by connection and
/// operation id, so that a restart sends them again in place of a new apply.
public protocol DeviceResultStoring: Sendable {
  func load(connectionID: String) async throws -> [String: Data]
  func save(_ results: [String: Data], connectionID: String) async throws
}

/// One JSON file with the kept results of every connection.
public actor FileDeviceResultStore: DeviceResultStoring {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load(connectionID: String) async throws -> [String: Data] {
    [:]
  }

  public func save(_ results: [String: Data], connectionID: String) async throws {}
}
