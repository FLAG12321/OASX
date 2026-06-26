## ADDED Requirements

### Requirement: Desktop launch at startup
The system SHALL allow desktop users to enable or disable launching OASX when the operating system user signs in.

#### Scenario: Enable launch at startup
- **WHEN** a desktop user enables launch at startup
- **THEN** the system persists the preference and configures the operating system to launch OASX on user sign-in

#### Scenario: Disable launch at startup
- **WHEN** a desktop user disables launch at startup
- **THEN** the system removes the operating system launch entry and persists the disabled state

#### Scenario: Refresh launch state
- **WHEN** the app starts on a desktop platform
- **THEN** the system reads the operating system launch entry and updates the visible launch-at-startup state

### Requirement: Automatic script run list
The system SHALL allow users to maintain a persisted list of scripts that run automatically after the app starts.

#### Scenario: Add script to automatic run list
- **WHEN** a user marks a script for automatic run
- **THEN** the system stores that script name in the automatic run list

#### Scenario: Remove script from automatic run list
- **WHEN** a user unmarks a script for automatic run
- **THEN** the system removes that script name from the automatic run list

#### Scenario: Restore automatic run list
- **WHEN** the app initializes the script service
- **THEN** the system restores the automatic run list from local storage

### Requirement: Run automatic scripts on app startup
The system SHALL start scripts from the automatic run list after the script service has initialized.

#### Scenario: Start configured scripts
- **WHEN** the app starts and the automatic run list contains valid scripts
- **THEN** the system starts each listed script through the existing script start flow and shows progress feedback

#### Scenario: Skip already running script
- **WHEN** an automatic-run script is already running
- **THEN** the system treats it as successful and continues with the remaining scripts

#### Scenario: Continue after failed script start
- **WHEN** an automatic-run script cannot be started within the expected timeout
- **THEN** the system continues processing the remaining automatic-run scripts without changing the backend protocol
