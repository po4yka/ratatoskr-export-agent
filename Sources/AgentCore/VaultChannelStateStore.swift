import Foundation
import os

/// What a restart needs to resume the `cli` channel of one vault. It holds no
/// secret: the device credential stays in the Keychain.
public struct VaultChannelState: Codable, Equatable, Sendable {
  public var vaultKey: String
  public var connectionID: String
  public var committedSequence: UInt64

  public init(vaultKey: String, connectionID: String, committedSequence: UInt64) {
    self.vaultKey = vaultKey
    self.connectionID = connectionID
    self.committedSequence = committedSequence
  }

  enum CodingKeys: String, CodingKey {
    case vaultKey = "vault_key"
    case connectionID = "connection_id"
    case committedSequence = "committed_sequence"
  }
}

public protocol VaultChannelStateStoring: Sendable {
  func load(vaultKey: String) async throws -> VaultChannelState?
  func save(_ state: VaultChannelState) async throws
  func remove(vaultKey: String) async throws
}

/// One JSON file, `{"vaults":[...]}`, with the state of every watched vault.
/// Each save writes the whole file atomically. A file that does not decode
/// is moved aside to `<name>.corrupt-<seconds>` with one log line, and the
/// store starts empty, so one bad file cannot stop the saves for good.
public actor FileVaultChannelStateStore: VaultChannelStateStoring {
  private struct Document: Codable {
    var vaults: [VaultChannelState]
  }

  private let fileURL: URL
  private let now: @Sendable () -> Date
  private let log: @Sendable (String) -> Void

  public init(
    fileURL: URL,
    now: @escaping @Sendable () -> Date = { Date() },
    log: @escaping @Sendable (String) -> Void = { line in
      Logger(subsystem: "ratatoskr.export-agent", category: "vault-channels").error("\(line, privacy: .public)")
    }
  ) {
    self.fileURL = fileURL
    self.now = now
    self.log = log
  }

  public func load(vaultKey: String) async throws -> VaultChannelState? {
    try document().vaults.first { $0.vaultKey == vaultKey }
  }

  public func save(_ state: VaultChannelState) async throws {
    var vaults = try document().vaults.filter { $0.vaultKey != state.vaultKey }
    vaults.append(state)
    try write(vaults)
  }

  private func write(_ unsorted: [VaultChannelState]) throws {
    let vaults = unsorted.sorted { $0.vaultKey < $1.vaultKey }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(Document(vaults: vaults)).write(to: fileURL, options: .atomic)
  }

  public func remove(vaultKey: String) async throws {
    let document = try document()
    guard document.vaults.contains(where: { $0.vaultKey == vaultKey }) else {
      return
    }
    try write(document.vaults.filter { $0.vaultKey != vaultKey })
  }

  private func document() throws -> Document {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return Document(vaults: [])
    }
    let data = try Data(contentsOf: fileURL)
    do {
      return try JSONDecoder().decode(Document.self, from: data)
    } catch {
      let aside = fileURL.deletingLastPathComponent()
        .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(Int(now().timeIntervalSince1970))")
      try FileManager.default.moveItem(at: fileURL, to: aside)
      log("The vault channel state did not decode; it was moved to \(aside.lastPathComponent), and the store starts empty.")
      return Document(vaults: [])
    }
  }
}
