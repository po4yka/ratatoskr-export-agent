# app-shell Specification

## Purpose
Pins how the agent process presents itself and starts: a menu-bar accessory application plus a headless smoke launch used to prove the real startup path in automation.

## Requirements

### Requirement: Accessory operation
On normal launch the agent SHALL activate the accessory presentation: no regular-application dock presence and no main window.

#### Scenario: Launch as menu-bar agent
- **WHEN** the process starts without arguments
- **THEN** it runs with the accessory activation policy and installs its status-bar item without opening a main window

### Requirement: Headless smoke mode exits successfully
With `--smoke`, the process SHALL execute the real startup path and terminate with exit code 0 within a bounded time.

#### Scenario: Smoke launch succeeds
- **WHEN** the release binary is launched with `--smoke`
- **THEN** the process reaches the running application state and exits with code 0 within the bounded interval

### Requirement: Unknown arguments are rejected
Unrecognized command-line arguments SHALL cause a non-zero exit with a usage message.

#### Scenario: Unrecognized flag
- **WHEN** the binary is launched with an argument it does not define
- **THEN** the process prints usage information to standard error and exits non-zero
