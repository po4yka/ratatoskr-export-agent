import Foundation

extension ObsidianCLIApply {
  static let invalidProperty = "export_agent.write.invalid_property"

  /// `property_change` `set` runs `obsidian property:set` with the JSON value
  /// that the content of the operation holds; `remove` runs
  /// `obsidian property:remove`. Nil when the CLI applied the change.
  func setProperty(_ operation: DeviceOperation, content: @Sendable () async throws -> Data) async throws -> DeviceOperationOutcome? {
    guard let key = operation.propertyKey, !key.isEmpty else {
      return .failed(code: Self.invalidProperty)
    }
    switch operation.propertyChange {
    case "remove":
      return await run(["property:remove", "name=\(key)", "path=\(operation.path)"])
    case "set":
      guard let value = Self.cliValue(of: try await content()) else {
        return .failed(code: Self.invalidProperty)
      }
      let type = value.type.map { ["type=\($0)"] } ?? []
      return await run(["property:set", "name=\(key)", "value=\(value.text)"] + type + ["path=\(operation.path)"])
    default:
      return .failed(code: Self.invalidProperty)
    }
  }

  /// The CLI text and type of a JSON value: a string as it is, a number as
  /// `number`, a boolean as `checkbox`, and an array of strings or numbers as
  /// a `list` with `, ` between the items. Nil for any other value.
  static func cliValue(of json: Data) -> (text: String, type: String?)? {
    guard let value = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]) else {
      return nil
    }
    switch value {
    case let text as String:
      return (text, nil)
    case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
      return (number.boolValue ? "true" : "false", "checkbox")
    case let number as NSNumber:
      return (number.stringValue, "number")
    case let items as [Any]:
      let texts = items.compactMap { item -> String? in
        (item as? String) ?? ((item as? NSNumber).map(\.stringValue))
      }
      return texts.count == items.count ? (texts.joined(separator: ", "), "list") : nil
    default:
      return nil
    }
  }
}
