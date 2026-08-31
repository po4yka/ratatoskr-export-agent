import Foundation

public protocol DeviceIdentityStoring: Sendable {
  func load() async throws -> PairedDeviceIdentity?
  func save(_ identity: PairedDeviceIdentity) async throws
  func remove() async throws
}

public actor InMemoryDeviceIdentityStore: DeviceIdentityStoring {
  private var identity: PairedDeviceIdentity?

  public init(identity: PairedDeviceIdentity? = nil) { self.identity = identity }
  public func load() async throws -> PairedDeviceIdentity? { identity }
  public func save(_ identity: PairedDeviceIdentity) async throws { self.identity = identity }
  public func remove() async throws { identity = nil }
}

public actor FileDeviceIdentityStore: DeviceIdentityStoring {
  private let fileURL: URL

  public init(fileURL: URL) { self.fileURL = fileURL }

  public func load() async throws -> PairedDeviceIdentity? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    do { return try JSONDecoder().decode(PairedDeviceIdentity.self, from: Data(contentsOf: fileURL)) }
    catch { throw DeviceCredentialError.unavailable }
  }

  public func save(_ identity: PairedDeviceIdentity) async throws {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try JSONEncoder().encode(identity).write(to: fileURL, options: .atomic)
    } catch { throw DeviceCredentialError.unavailable }
  }

  public func remove() async throws {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    do { try FileManager.default.removeItem(at: fileURL) }
    catch { throw DeviceCredentialError.unavailable }
  }
}
