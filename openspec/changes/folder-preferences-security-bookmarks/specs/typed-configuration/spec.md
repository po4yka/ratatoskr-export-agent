## MODIFIED Requirements

### Requirement: Missing configuration yields defaults
Loading the configuration SHALL succeed with the documented default configuration when the file does not exist at the configured location. The defaults SHALL leave the backend endpoint unset.

#### Scenario: Startup without a configuration file
- **WHEN** the configuration file is absent
- **THEN** loading succeeds and returns the default configuration with no backend endpoint

## REMOVED Requirements

### Requirement: Watched folder entries are usable
**Reason**: Watched-folder ownership moves to the dedicated per-folder preferences registry (capability `watched-folder-preferences`), which carries security-scoped bookmarks and per-folder settings that a bare path-string list cannot express; keeping both would leave two sources of truth for which folders are watched.
**Migration**: Manage watched folders exclusively through the preferences registry. The configuration document no longer declares `watchedFolders`, and documents containing it are rejected as unknown fields.
