## Purpose

Owns the persisted registry of user-chosen watched folders: one document holding each folder's stable identity, sanitized display metadata, enabled flag, archive-after-upload policy, and security-scoped bookmark bytes, plus the settings surface where folders are managed.

## ADDED Requirements

### Requirement: Picked folder is stored persistently
Adding a user-picked folder SHALL create exactly one registry entry carrying a stable generated ID, the folder's display path as sanitized metadata, enabled state defaulting to on, the default archive-after-upload policy, and non-empty bookmark data. Reloading the document from disk SHALL restore the identical entry set.

#### Scenario: Added folder survives reload
- **WHEN** a picked folder URL is added to the registry and the document is saved and reloaded from disk
- **THEN** the entry is present with its display path, enabled-by-default state, default archive policy, and non-empty bookmark data

#### Scenario: Adding the same folder twice yields one entry
- **WHEN** the same folder URL is added while an entry for that folder already exists
- **THEN** the registry still holds exactly one entry for that folder and no duplicate is created

### Requirement: Per-folder settings persist
Each entry SHALL carry an enabled flag and an archive policy selecting between preserving in place and archiving after upload. Changing either SHALL persist and survive reload.

#### Scenario: Disable toggle persists
- **WHEN** a folder entry is disabled and the document is reloaded from disk
- **THEN** the entry loads with enabled equal to false

#### Scenario: Archive-policy change persists
- **WHEN** a folder's archive policy is changed to preserve-in-place and the document is reloaded from disk
- **THEN** the entry loads with the preserve-in-place policy

### Requirement: Document validation is strict
The preferences document SHALL declare schema version 1 and SHALL reject unknown fields, unsupported or missing versions, duplicate folder identities, and empty bookmark data, naming the offending field or entry. Validation failures SHALL identify the file location and reason without embedding raw file contents.

#### Scenario: Unsupported schema version rejected
- **WHEN** the preferences document declares a version other than 1
- **THEN** loading fails stating only schema version 1 is supported

#### Scenario: Unknown field rejected
- **WHEN** the preferences document contains a field outside schema version 1
- **THEN** loading fails and reports the unknown field name

#### Scenario: Duplicate folder identity rejected
- **WHEN** two entries declare the same folder ID
- **THEN** loading fails and reports the duplicated ID

#### Scenario: Empty bookmark data rejected
- **WHEN** an entry carries empty bookmark data
- **THEN** loading fails and reports the offending entry

#### Scenario: Error report shape
- **WHEN** preferences loading fails validation
- **THEN** the reported error names the preferences file path and the reason, and contains none of the file's raw contents

### Requirement: Removing a folder relinquishes its access
Removing an entry SHALL stop any scoped access held for that folder and drop its stored bookmark data so nothing resolvable remains.

#### Scenario: Removed folder leaves nothing behind
- **WHEN** a registered folder is removed and the document is reloaded from disk
- **THEN** no entry for that folder remains and its bookmark bytes are absent from the document

### Requirement: Settings window manages the registry
Choosing Settings from the status-bar menu SHALL open a window listing one row per registered folder, each row showing its display path, an enable toggle, an archive-policy selection, a remove action, and the folder's current access state. Adding runs a folder picker; removal asks for confirmation before deleting the entry.

#### Scenario: Registered folders appear in the settings window
- **WHEN** the settings window opens with a populated registry
- **THEN** it shows one row per registered folder with its enable toggle, archive-policy selection, remove action, and access state

#### Scenario: Remove requires confirmation
- **WHEN** the user removes a folder row and declines the confirmation
- **THEN** the entry remains registered and unchanged

### Requirement: Persistence precedes reported success
An add SHALL persist the new entry atomically before the settings surface reports the folder as added; when persistence fails, the registry SHALL remain unchanged and the failure SHALL be surfaced instead of silently swallowed.

#### Scenario: Save failure leaves registry unchanged
- **WHEN** adding a folder and saving the document fails
- **THEN** the in-memory registry still excludes that folder and the settings surface reports the failure
