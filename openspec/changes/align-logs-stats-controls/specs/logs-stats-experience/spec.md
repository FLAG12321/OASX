## ADDED Requirements

### Requirement: Load historical logs
The system SHALL display previously existing script run logs when the Logs view is opened, not only logs generated in the current session.

#### Scenario: Open Logs view with existing logs
- **WHEN** the user opens the Logs view and previous script logs exist
- **THEN** the system loads and displays the latest historical log window together with any new live logs

#### Scenario: Lazy-load older logs
- **WHEN** the user scrolls upward near the top of the currently loaded Logs view and older script logs exist
- **THEN** the system loads an older log window and prepends it without losing the user's current viewport position

#### Scenario: Reach beginning of log history
- **WHEN** the user scrolls upward after all older script logs have already been loaded
- **THEN** the system stops requesting older logs and keeps the currently displayed logs visible

#### Scenario: Restore scroll position
- **WHEN** the Logs view is reopened after scrolling
- **THEN** the system restores the saved scroll offset behavior consistent with the source project

#### Scenario: Historical log source unavailable
- **WHEN** the historical script log window cannot be loaded
- **THEN** the system continues showing the existing live log stream without blocking the Logs view

### Requirement: Remove manual stats refresh
The system SHALL NOT present a manual refresh control on the Stats view.

#### Scenario: Stats view controls
- **WHEN** the user opens the Stats view
- **THEN** the system shows no manual refresh button while statistics continue to update through the existing automatic flow

### Requirement: Log actions visible only on Logs tab
The system SHALL show log action controls (copy, auto-scroll, clear) only while the Logs tab is active.

#### Scenario: Log actions on Logs tab
- **WHEN** the Logs tab is active
- **THEN** the system shows the copy, auto-scroll, and clear log controls

#### Scenario: Log actions hidden on Stats tab
- **WHEN** the Stats tab is active
- **THEN** the system hides the copy, auto-scroll, and clear log controls

#### Scenario: Switch back to Logs restores actions
- **WHEN** the user switches from the Stats tab back to the Logs tab
- **THEN** the system shows the log action controls again
