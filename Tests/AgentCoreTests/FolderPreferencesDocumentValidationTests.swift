import AgentCore
import XCTest

final class FolderPreferencesDocumentValidationTests: XCTestCase {
  private func writePreferencesDocument(_ json: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ratatoskr-preferences-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    return url
  }

  private func entryJSON(
    id: String = "11111111-1111-1111-1111-111111111111",
    displayPath: String = "/Users/somebody/Ratatoskr Inbox",
    enabled: Bool = true,
    archivePolicy: String = "archiveAfterUpload",
    bookmarkDataBase64: String = "c3ludGhldGljLWJvb2ttYXJr"
  ) -> String {
    """
    {"id": "\(id)", "displayPath": "\(displayPath)", "enabled": \(enabled), \
    "archivePolicy": "\(archivePolicy)", "bookmarkDataBase64": "\(bookmarkDataBase64)"}
    """
  }

  func testUnsupportedSchemaVersionFails() throws {
    let url = try writePreferencesDocument(#"{"schemaVersion": 2, "folders": []}"#)

    XCTAssertThrowsError(try FolderPreferences.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains("schema version 1"),
        "expected the error to state support for schema version 1 only, got: \(error)"
      )
    }
  }

  func testUnknownFieldIsRejectedAndNamed() throws {
    let url = try writePreferencesDocument(
      #"{"schemaVersion": 1, "folders": [], "unexpected": true}"#
    )

    XCTAssertThrowsError(try FolderPreferences.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains("unexpected"),
        "expected the error to name the unknown field, got: \(error)"
      )
    }
  }

  func testDuplicateFolderIDFailsNamingTheID() throws {
    let fixedID = "11111111-1111-1111-1111-111111111111"
    let url = try writePreferencesDocument(
      """
      {"schemaVersion": 1, "folders": [\(entryJSON(id: fixedID)), \(entryJSON(id: fixedID))]}
      """
    )

    XCTAssertThrowsError(try FolderPreferences.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains(fixedID),
        "expected the error to name the duplicated folder ID, got: \(error)"
      )
    }
  }

  func testEmptyBookmarkDataFailsNamingTheEntry() throws {
    let emptyBookmarkID = "22222222-2222-2222-2222-222222222222"
    let url = try writePreferencesDocument(
      """
      {"schemaVersion": 1, "folders": [\(entryJSON(id: emptyBookmarkID, bookmarkDataBase64: ""))]}
      """
    )

    XCTAssertThrowsError(try FolderPreferences.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains(emptyBookmarkID),
        "expected the error to name the offending entry, got: \(error)"
      )
    }
  }

  func testValidationErrorNamesFileAndReasonWithoutContents() throws {
    let privatePath = "/Users/somebody/private/inbox"
    let url = try writePreferencesDocument(
      """
      {"schemaVersion": 1, "folders": [\
      \(entryJSON(displayPath: privatePath)), \
      \(entryJSON(displayPath: privatePath))]}
      """
    )

    XCTAssertThrowsError(try FolderPreferences.load(from: url)) { error in
      let description = String(describing: error)
      XCTAssertTrue(
        description.contains(url.path),
        "expected the error to name the preferences file, got: \(description)"
      )
      XCTAssertTrue(
        description.contains("duplicated"),
        "expected the error to state the reason, got: \(description)"
      )
      XCTAssertFalse(
        description.contains(privatePath),
        "expected the error not to embed raw file contents, got: \(description)"
      )
    }
  }
}
