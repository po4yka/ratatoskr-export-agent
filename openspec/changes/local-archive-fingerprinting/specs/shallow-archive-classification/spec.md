## Purpose

Labels an archive candidate's container format and probable provider from cheap, bounded evidence - magic bytes and shallow structure only - so routing metadata exists before upload. Provider services keep schema detection and completeness authority; this classification never decompresses or deeply parses content.

## ADDED Requirements

### Requirement: Container type is sniffed from magic bytes

The classifier SHALL identify the container from leading bytes: a file starting with the ZIP local-file-header signature is `zip`, a file whose first non-whitespace byte opens a JSON object or array is `json`, and anything else is an unknown container.

#### Scenario: ZIP archive recognized by signature

- **WHEN** classification runs over a file beginning with the bytes `PK\x03\x04`
- **THEN** the reported container is zip

#### Scenario: JSON document recognized by shape

- **WHEN** classification runs over a UTF-8 file whose content begins (after optional whitespace) with `{` or `[` and parses as a bounded prefix of valid JSON
- **THEN** the reported container is json

#### Scenario: Unrecognized bytes yield an unknown container

- **WHEN** classification runs over a file that starts with neither signature, such as plain text
- **THEN** the reported container is unknown and no provider label is claimed

### Requirement: ZIP candidates are labelled from central-directory entry names only

For a zip candidate the classifier SHALL read entry names from the archive's central directory within a bounded scan and match them against provider marker rows. A row matching all its required markers for exactly one provider SHALL label that provider with strong confidence; partial evidence for one provider only SHALL label it probable; evidence satisfying rows of more than one provider SHALL report ambiguous; no row matching SHALL report unidentified.

#### Scenario: ChatGPT export markers label ChatGPT

- **WHEN** a synthetic zip contains top-level entries `conversations.json` and `user.json`
- **THEN** classification reports provider chatgpt with strong confidence and records the matched markers as evidence

#### Scenario: Claude export markers label Claude

- **WHEN** a synthetic zip contains top-level entries `conversations.json` and `users.json`
- **THEN** classification reports provider claude with strong confidence

#### Scenario: Instagram activity layout labels Instagram

- **WHEN** a synthetic zip contains entries under a top-level `your_instagram_activity/` folder
- **THEN** classification reports provider instagram

#### Scenario: Threads markers label Threads

- **WHEN** a synthetic zip contains a top-level threads marker set defined by the classifier's table
- **THEN** classification reports provider threads

#### Scenario: Overlapping weak evidence reports ambiguity rather than guessing

- **WHEN** a zip's entry names partially satisfy marker rows belonging to different providers without fully confirming either
- **THEN** classification reports ambiguous instead of choosing a provider

#### Scenario: Marker-less zip stays unidentified

- **WHEN** a synthetic zip contains none of any provider's markers
- **THEN** classification reports unidentified while still reporting the zip container

### Requirement: JSON candidates are probed by top-level structure only

For a json candidate the classifier SHALL inspect at most a bounded prefix covering the top-level structure - the keys of the root object or of the first objects of a root array - and apply the same provider labelling rules as zips.

#### Scenario: Conversation-array shape labels its provider

- **WHEN** a json fixture holds an array whose first element carries the conversation-object key set of exactly one provider row
- **THEN** classification labels that provider from the structural evidence alone

#### Scenario: Deep content is not inspected

- **WHEN** a json fixture nests additional objects far beyond the top level
- **THEN** classification reaches its verdict without requiring those nested levels to be present or parsed

### Requirement: Classification is advisory and bounded

Classification SHALL record the method and matched markers as evidence, SHALL NOT decompress zip entry contents, SHALL NOT read beyond its bounded probes regardless of file size, and SHALL treat unidentified outcomes as normal results rather than failures.

#### Scenario: Unidentified candidate classifies cleanly

- **WHEN** an unrecognizable binary file is classified
- **THEN** the outcome reports an unknown container and unidentified provider without throwing

#### Scenario: Huge archives classify within bounds

- **WHEN** classification runs over a large zip whose central directory exceeds the bounded scan window
- **THEN** the classifier still terminates using only the bounded window and reports accordingly
