# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Planned
- Developer ID signing and macOS notarization
- Homebrew cask installation
- ADB port forwarding management panel
- Clipboard sync between Mac and connected device
- Device log (logcat) viewer accessible from the running device card
- Advanced emulator controls (snapshot save/load)
- Notification when a long-booting emulator becomes ready

---

## [1.2.4] - 2026-05-19

### Fixed
- **Global keyboard shortcut (⌥⌘X) reliability** — Switched the shortcut from `NSEvent.addGlobalMonitorForEvents` to Carbon's `RegisterEventHotKey`, so it now works without requiring Accessibility permission in System Settings. Also fixed a cold-launch bug where ⌥⌘X did nothing until the menu bar icon had been clicked at least once: SwiftUI's `MenuBarExtra(.window)` lazily instantiates its panel on first click, so the toggle now bootstraps the panel by clicking the status item when no panel window exists yet.

---

## [1.2.3] - 2026-05-15

### Changed
- **Swift 6 and macOS 14.6 minimum** — Bumped `SWIFT_VERSION` to 6.0 and `MACOSX_DEPLOYMENT_TARGET` to 14.6 for both Debug and Release configurations.
- **Bundle metadata** — Added `CFBundleDisplayName` (EmuHub) and `LSApplicationCategoryType` (`public.app-category.developer-tools`) so the app shows the correct display name and category in Finder, Spotlight, and System Settings.
- Refreshed macOS app icons.

---

## [1.2.2] - 2026-04-10

### Added
- **Global keyboard shortcut (⌥⌘X)** — Press Option+Command+X from anywhere to open or close the EmuHub menu bar popover. The global shortcut (opening from background) requires Accessibility permission in System Settings; the local shortcut (closing when popover is open) works without any extra permission.
- **Wi-Fi device detection** — Physical devices connected via ADB Wireless Debugging (Android 11+ TLS pairing, serial format `adb-…._adb-tls-connect._tcp`) and legacy `adb connect` (IP:port) are now correctly labelled **Wi-Fi connected** instead of USB. Offline status messages also distinguish the connection type.

### Fixed
- **ADB device parser rewritten** — replaced naive whitespace splitting with a regex-anchored parser that correctly handles serials containing spaces (e.g., ADB TLS wireless serials like `adb-XYZ (2)._adb-tls-connect._tcp`). The old parser would truncate these serials at the first space, causing Wi-Fi devices to fall through to USB classification.
- **Wireless serial normalization** — the ` (N)` duplicate-session suffix that ADB TLS can append when the same device opens a second connection is now stripped before classification and deduplication, so `adb-XYZ (2)._adb-tls-connect._tcp` and `adb-XYZ._adb-tls-connect._tcp` are treated as one device.
- **Duplicate device entries eliminated** — deduplication now operates on normalized serials; when two entries share a canonical serial the one with the higher `transport_id` (most recent connection) is kept.
- **Connection-aware removal guidance** — the error shown when a user tries to stop a physical device now says "disable Wireless Debugging" for Wi-Fi devices instead of always saying "unplug the USB cable".

---

## [1.2.1] - 2026-04-10

### Changed
- **Help section expanded** — Added coverage for all features introduced in 1.2.0 that were missing from the FAQ: Cold Boot and Wipe & Boot launch options, screenshot capture, APK drag-and-drop install, AVD search/filter, Create AVD workflow, Launch at Login, and the in-app Software Update flow.
- Added a new **Device Actions** section to the Help view grouping screenshot and APK install topics together.
- Added a Troubleshooting entry for AVD creation failures caused by a missing `avdmanager` / Android Command-line Tools installation.

---

## [1.2.0] - 2026-04-09

### Added
- **Create AVD** — New dedicated page (tap `+` next to the Available header) for creating Android Virtual Devices without opening Android Studio or Terminal.
  - System image picker — scans `$SDK/system-images/` for installed images, sorted by API level (newest first), showing type (Google APIs / Google Play / AOSP) and ABI.
  - Hardware profile picker — populated via `avdmanager list device`, with Pixel 7 pre-selected when available.
  - Name field auto-replaces spaces with underscores to satisfy `avdmanager` naming rules; live preview shows the final name.
  - Resolves `avdmanager` from `cmdline-tools/latest`, any versioned cmdline-tools directory, or the legacy `tools/bin` path.
  - Inline spinner while creation runs; green success banner and automatic AVD list refresh on completion.
- **Screenshot capture** — Camera button (fade-in on hover) on any running device card saves a PNG to the Desktop and reveals it in Finder.
- **Cold Boot & Wipe Data & Boot** — Right-click an AVD card to cold-boot (`-no-snapshot-load`) or wipe and boot (`-wipe-data`). Duplicate flags between shortcut and user-configured extra args are deduplicated automatically.
- **APK drag-and-drop install** — Drop any `.apk` onto a running device card. A blue drop-target border and overlay appear during the drag; an inline spinner replaces card actions while the install runs; a success banner confirms completion.
- **AVD search/filter** — Magnifying glass icon in the Available header toggles a search field. Typed text filters the list in real time (case-insensitive). Dismissing or clearing the field collapses it automatically.
- **Transient action feedback** — Green `ActionBanner` above the device list confirms operations (screenshot, APK install, AVD creation) and auto-dismisses after 3 seconds.
- **Physical device name resolution** — Authorized physical devices now show the resolved model name (e.g., "Pixel 8 Pro") and Android version fetched via `adb shell getprop`.
- **Running emulator identification** — Running emulators display the AVD name (e.g., "Pixel 7") resolved via `adb emu avd name` instead of "Android Emulator".
- **Device property caching** — Physical device properties are cached in-session to avoid repeated adb queries on every auto-refresh.
- **Concurrent device enrichment** — Model name, Android version, and AVD name queries run concurrently via `withTaskGroup`.
- **Device-type-aware icons** — AVD cards display icons and accent colors by form factor: phone (blue), tablet (indigo), TV (purple), Wear OS (pink), Automotive (green), Foldable (orange).
- **Running emulator port display** — Emulator status includes the adb port (e.g., "Emulator running · port 5554").

### Changed
- AVD cards expose a right-click context menu with Launch, Cold Boot, and Wipe Data & Boot.
- Physical device cards show the resolved model name as the primary label and Android version + state as the subtitle.
- Running emulator cards show the resolved AVD name instead of a generic label.
- AVD subtitle reflects the device category (e.g., "API 34 · Virtual Device", "API 33 · Android TV").
- Launch button accent color matches the device-type color.
- `stop()` error message explicitly references USB cable and USB debugging for clearer guidance.
- `AppRoute` uses an explicit `menuItems` array so the Create AVD route does not appear in the hamburger menu.
- `Shell.run` accepts an optional `stdin: Data?` parameter used when running `avdmanager create avd`.

### Fixed
- Empty strings from `adb shell getprop` are treated as missing rather than displayed as blank labels.
- Device enrichment is skipped for offline and unauthorized devices, preventing adb timeout delays during refresh.

---

## [1.1.4] - 2026-02-20

### Added
- In-app **Check for Updates** flow from the quick actions menu.
- GitHub Releases integration (`/releases/latest`) to compare the installed app version against the newest published release.
- Direct release actions from the update panel (open release notes and download latest artifact when available).

### Changed
- Update version comparison now normalizes release tags and treats semantic equivalents as equal.

### Fixed
- "Check for Updates" now handles equal versions gracefully by showing that the user already has the latest version.
- Prevented false-positive update prompts caused by release metadata suffixes like `+build` or `-beta`.

---

## [1.1.3] - 2026-02-05

### Added
- Added an **About** section in Settings with:
  - App identity text
  - Runtime version/build display
  - Quick links to repository, changelog, and license

### Changed
- Updated menu header branding to **EmuHub**.
- Added compact header counts for emulator and physical device totals.
- Updated Running section empty-state message to **"No connected devices"** for clearer wording.
- Added footer refresh recency text (`Updated ...`) backed by tracked refresh timestamps.

### Fixed
- Improved physical-device status pill labeling to correctly show **Authorize**, **Offline**, or **Connected** instead of overly generic state wording.

---

## [1.1.2] - 2026-02-05

### Added
- Automated macOS CI build using GitHub Actions
- Automatic version tagging based on app version
- Automated GitHub Releases with downloadable `.app` archive
- CONTRIBUTING guidelines for open-source contributors
- Pull Request template
- CODEOWNERS file for repository governance

### Changed
- Introduced `dev → main` workflow for releases
- Enforced branch protection rules on `main`
- Improved open-source readiness and repository structure

### Fixed
- CI build failures caused by macOS signing requirements
- Release workflow not triggering on version tags

---

## [1.1.0] - 2026-02-05

### Added
- Display of connected physical Android devices alongside emulators
- Clear differentiation between Android emulators and physical devices
- Device state handling for physical devices (`device`, `unauthorized`, `offline`)
- Informative UI messaging for unauthorized devices (USB debugging not yet approved)

### Changed
- Running section now represents **all connected devices**, not just emulators
- Emulator-only actions are restricted to emulators
- Improved UX messaging instead of generic command failure errors

### Fixed
- Prevented `adb emu kill` from being executed on physical devices
- Eliminated misleading `Command failed (exit 1)` errors when phones are connected
- Improved safety checks around emulator stop actions

---

## [1.0.0] - 2026-01-29

### Added
- Initial public release of EmuHub
- macOS menu bar application for managing Android Emulators (AVDs)
- Detection of available Android Virtual Devices
- Ability to start emulators with configurable launch arguments
- Detection of running emulators via `adb`
- Clean shutdown of running emulators using `adb emu kill`
- Settings panel for Android SDK path and emulator options
- Automatic periodic refresh of emulator state

### Notes
- This release is signed with an Apple Personal Team and is not notarized
- macOS may prompt for security approval on first launch
- Designed for local developer use
