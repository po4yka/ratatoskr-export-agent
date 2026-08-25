# privacy-logging Specification

## Purpose
Guarantees that log output never exposes filesystem locations by default while staying useful for local diagnostics through an explicit operator-controlled toggle.

## Requirements

### Requirement: Paths are redacted by default
Log output SHALL NOT contain filesystem paths or filenames unless redaction has been explicitly disabled. Matching content SHALL be replaced by a fixed placeholder.

#### Scenario: Absolute path in a log message
- **WHEN** a message containing an absolute filesystem path is logged
- **THEN** the emitted output contains a placeholder instead of the path, including its final filename component

#### Scenario: Bare filename in a log message
- **WHEN** a message containing a bare filename with an extension is logged
- **THEN** the emitted output contains a placeholder instead of the filename

### Requirement: Redaction applies across levels
Redaction SHALL apply identically at every log level and category.

#### Scenario: Debug level is also redacted
- **WHEN** a path-containing message is logged at debug level
- **THEN** the output is redacted like any other level

### Requirement: Explicit toggle disables redaction
When the operator enables verbose logging, redaction SHALL be disabled so paths appear verbatim; without the toggle redaction SHALL remain active.

#### Scenario: Verbose toggle reveals paths
- **WHEN** logging runs with the verbose toggle enabled and a path-containing message is logged
- **THEN** the emitted output contains the original path unchanged

#### Scenario: Toggle off keeps redaction on
- **WHEN** logging runs without the verbose toggle and the same message is logged
- **THEN** the emitted output contains the placeholder

### Requirement: Non-path content passes through unchanged
Messages without path-like content SHALL be emitted verbatim under redaction.

#### Scenario: Ordinary message unaffected
- **WHEN** a message without filesystem references is logged
- **THEN** the emitted output equals the input
