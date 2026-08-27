import Foundation

public protocol SupportReportWriting: Sendable {
  func write(_ data: Data, to destination: URL) throws
}

public struct AtomicSupportReportWriter: SupportReportWriting, Sendable {
  public init() {}

  public func write(_ data: Data, to destination: URL) throws {
    try data.write(to: destination, options: .atomic)
  }
}

public struct SupportReportExporter: Sendable {
  private let writer: any SupportReportWriting

  public init(writer: any SupportReportWriting = AtomicSupportReportWriter()) {
    self.writer = writer
  }

  public func export(previewData: Data, to destination: URL) throws {
    try writer.write(previewData, to: destination)
  }
}
