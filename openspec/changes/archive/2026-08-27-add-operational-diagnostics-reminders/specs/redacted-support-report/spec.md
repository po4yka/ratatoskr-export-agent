## Purpose

Produces a reviewable support artifact that is useful for troubleshooting while excluding sensitive export data unless the user selects a specific field for a specific item.

## ADDED Requirements

### Requirement: Default support report is redacted by construction
The default report SHALL be encoded from a closed schema containing only report time, application/build facts, diagnostic enums, bounded counters, byte counts, durations, and shortened digest prefixes. The schema MUST NOT admit arbitrary metadata, filenames, filesystem paths, archive contents, credentials, endpoint URLs, backend private errors, full digests, or opaque tokens.

#### Scenario: Sensitive source facts cannot enter the default report
- **WHEN** diagnostics are assembled from entries that have filenames, paths, URLs, content, credentials, and full digests available elsewhere in memory
- **THEN** the default encoded report contains only approved enums, counters, byte values, times, and shortened digest prefixes

#### Scenario: Malicious text cannot escape through a diagnostic field
- **WHEN** a source error or label contains a path, credential-bearing URL, or archive text
- **THEN** the report maps it to a bounded classification rather than encoding the source text

### Requirement: Sensitive per-item detail requires explicit field selection
The report SHALL include a filename, bounded text detail, or URL only when the user explicitly selects that field for that specific item after reviewing the value. Selection of one field or item MUST NOT authorize any other field or item, and filesystem paths and credentials MUST remain prohibited.

#### Scenario: One reviewed filename is included narrowly
- **WHEN** the user explicitly selects the filename field for one reviewed item and selects no URL or text detail
- **THEN** the report includes that filename for only that item and includes no URL or text detail

#### Scenario: No selection preserves the safe default
- **WHEN** the user exports without selecting any per-item fields
- **THEN** the report contains no filename, content, or URL field for any item

### Requirement: Report export is local and reviewable
The agent SHALL render the complete report for review before writing a user-chosen local file. A failed export MUST leave the diagnostics panel usable and MUST NOT upload or transmit any report bytes.

#### Scenario: User exports a reviewed report
- **WHEN** the user confirms a report preview and chooses a writable destination
- **THEN** exactly the previewed bytes are written locally and no network transmission occurs
