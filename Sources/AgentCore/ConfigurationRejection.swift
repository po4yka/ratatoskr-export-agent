import Foundation

enum DocumentRejection: Error, CustomStringConvertible {
  case unsupportedSchemaVersion(Int?)
  case unknownField(String)
  case insecureBackendEndpoint(String)
  case nonPositiveValue(field: String, value: Int)
  case outOfRangeValue(field: String, value: Int, minimum: Int, maximum: Int)
  case incompatibleTransferCaps(chunkBytes: Int, bytesPerSecond: Int)

  var description: String {
    switch self {
    case let .unsupportedSchemaVersion(.some(actual)):
      "only schema version 1 is supported, found \(actual)"
    case .unsupportedSchemaVersion(.none):
      "only schema version 1 is supported, none declared"
    case let .unknownField(name):
      "unknown configuration field \"\(name)\""
    case let .insecureBackendEndpoint(endpoint):
      "backend endpoint must use https or plain http on a loopback host, got \(endpoint)"
    case let .nonPositiveValue(field, value):
      "configuration field \"\(field)\" must be greater than zero, got \(value)"
    case let .outOfRangeValue(field, value, minimum, maximum):
      "configuration field \"\(field)\" must be between \(minimum) and \(maximum), got \(value)"
    case let .incompatibleTransferCaps(chunkBytes, bytesPerSecond):
      "configuration field \"maxUploadBytesPerSecond\" must admit one uploadChunkBytes value; got \(bytesPerSecond) for chunk \(chunkBytes)"
    }
  }
}
