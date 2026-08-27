## Purpose

Defines a dependency-free, privacy-preserving update experience in which the user explicitly chooses to visit the trusted release page and the agent never fabricates update availability.

## ADDED Requirements

### Requirement: Updates are manual and user-initiated
The application SHALL expose a `Check for Updates…` action that opens `https://github.com/po4yka/ratatoskr-export-agent/releases/latest` in the user's default browser only after explicit selection. The application MUST NOT fetch an update feed, poll for releases, download executable code, install an update, or add an updater background process.

#### Scenario: User chooses update action
- **WHEN** the user selects `Check for Updates…`
- **THEN** the application asks the system to open the fixed HTTPS releases destination exactly once

#### Scenario: User takes no update action
- **WHEN** the application launches and remains running without the user selecting `Check for Updates…`
- **THEN** no update-related network request, browser open, download, or update timer occurs

### Requirement: Update destination is closed and trusted
The update action SHALL accept only the compiled-in Ratatoskr Export Agent GitHub Releases HTTPS URL and MUST NOT derive a destination from archive data, configuration, backend responses, redirects handled inside the agent, or user-controlled text.

#### Scenario: Update destination is inspected
- **WHEN** the update action's destination is validated
- **THEN** it is HTTPS, has host `github.com`, and has the exact Ratatoskr Export Agent latest-release path

### Requirement: Current version is presented truthfully
The update presentation SHALL show the current application short version from signed bundle metadata when available and SHALL report it as unavailable rather than substituting a build guess when metadata is missing.

#### Scenario: Bundle version is available
- **WHEN** update presentation receives a non-empty bundle short version
- **THEN** it displays that exact version alongside the manual-download explanation

#### Scenario: Bundle version is unavailable
- **WHEN** update presentation cannot read a non-empty bundle short version
- **THEN** it displays current version as unavailable and still makes no claim that a newer release exists

### Requirement: Browser-open failure is actionable
The application SHALL report that it could not open the releases page when the system refuses the update URL and SHALL leave installation and retry under user control.

#### Scenario: System refuses the releases URL
- **WHEN** the user selects the update action and the system reports that the URL was not opened
- **THEN** the application presents a generic actionable error without exposing archive, path, credential, or endpoint data
