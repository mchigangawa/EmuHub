# EmuHub Marketing Website Brief (for AI Site Builder)

## Product Snapshot
**EmuHub** is a macOS menu bar app that gives Android developers one-click control and visibility over local Android emulators (AVDs) and connected physical devices—without using Terminal.

## Core Value Proposition
- **Instant control from the menu bar**: launch/stop AVDs in a lightweight popover.
- **Unified device visibility**: see running emulators and real devices in one place.
- **Terminal-free workflow**: friendly UI wraps adb/emulator commands.
- **Built for developer flow**: keyboard shortcut, auto-refresh, quick diagnostics, and update checks.

## Feature Inventory (Use as Website Content Source)

### 1) Emulator Management
- Lists all configured AVDs with device-type icons (phone/tablet/TV/Wear/Automotive).
- Launch any AVD in one click.
- Stop running emulators cleanly via `adb emu kill`.
- Shows active emulator port and resolved AVD name.

### 2) Physical Device Visibility
- Auto-detects Android devices connected over USB or Wi-Fi (ADB wireless debugging).
- Resolves real model names (e.g., Pixel, Samsung Galaxy) and Android versions.
- Shows device state labels such as unauthorized/offline with clear guidance.
- Indicates connection type (USB/Wi-Fi).
- Deduplicates duplicate Wi-Fi + emulator serial scenarios.

### 3) Productivity & UX
- Global keyboard shortcut: **⌥⌘X** to open/close popover.
- Adjustable auto-refresh (3–60 seconds).
- Manual and auto-detected Android SDK path.
- Custom emulator launch flags (`-no-snapshot-load`, `-gpu host`, etc.).
- Launch at login (macOS 14+).

### 4) Update Experience
- Built-in GitHub Releases checker.
- Compares installed version to latest release.
- Provides direct download action when update is available.

### 5) Safety & Clarity
- Physical devices are intentionally **read-only** in UI (no accidental destructive actions).
- Fast status feedback for offline/unauthorized states.

## Target Audience
- Android app developers on macOS.
- QA engineers testing on multiple AVD/device combinations.
- Mobile teams who frequently switch between emulator profiles and real hardware.
- Developer advocates/instructors doing live demos.

## Messaging Pillars
1. **Focus**: “Control Android devices from your Mac menu bar.”
2. **Speed**: “Launch, monitor, and stop emulators in seconds.”
3. **Confidence**: “Clear device status and safe handling of physical hardware.”
4. **Simplicity**: “No Terminal required.”

## Differentiators
- Native macOS menu bar workflow (always one click away).
- Combines AVD controls and physical-device observability.
- Lightweight, purpose-built utility vs heavy IDE navigation.

## Suggested Website Information Architecture (Next.js)
1. **Hero**
   - Headline: “Your Android Device Hub, in the Mac Menu Bar.”
   - Subhead: “Launch AVDs, monitor real devices, and troubleshoot faster—without Terminal.”
   - CTAs: “Download for macOS”, “View on GitHub”.
2. **Social Proof / Trust Bar**
   - “Open source”, “Built with SwiftUI”, “Works with Android SDK tools”.
3. **Feature Grid**
   - Emulator control, Physical device visibility, Keyboard shortcut, Smart status insights.
4. **How It Works (3 Steps)**
   - Open menu bar app → choose AVD/device → act instantly.
5. **Use Cases**
   - Daily Android development, QA regression sweeps, workshop/demo setup.
6. **System Requirements**
   - macOS 14+, Android SDK installed.
7. **FAQ**
   - Notarization note, Accessibility permission for hotkey, offline/unauthorized fixes.
8. **Final CTA**
   - Download latest release + link to docs/README.

## Brand & Visual Direction

### App-Informed Color Guidance
Use a cool, developer-oriented palette centered on **blue + purple gradients**, with cyan as optional accent for update-related callouts.

- **Primary Blue**: `#3B82F6` (Tailwind `blue-500` equivalent)
- **Primary Purple**: `#8B5CF6` (Tailwind `violet-500` equivalent)
- **Accent Cyan (optional)**: `#06B6D4`
- **Success Green**: `#22C55E`
- **Warning Orange**: `#F59E0B`
- **Error Red**: `#EF4444`
- **Neutrals**: slate/zinc gray scale for text/surfaces

### Gradient Direction
- Preferred hero gradient: **top-left blue → bottom-right purple**.
- Secondary callout gradient (updates): **blue → cyan**.

### UI Tone
- Clean, minimal, technical, and high signal.
- Avoid playful consumer visuals; favor precision and clarity.

## Copy Blocks (Ready to Reuse)

### Hero
“Manage Android emulators and devices from your Mac menu bar. EmuHub gives you instant visibility and one-click actions—without touching Terminal.”

### Short Product Description
“EmuHub is a lightweight macOS utility for Android developers that unifies AVD controls and connected device status in one fast menu bar app.”

### CTA Variants
- “Download EmuHub”
- “Get the Latest Release”
- “View Documentation”
- “Explore on GitHub”

## SEO Seeds
- android emulator manager mac
- adb device monitor macOS
- menu bar app for android development
- mac utility for android studio workflows
- launch avd from mac menu bar

## Content Constraints / Accuracy Notes
- Position EmuHub as **macOS-only**.
- Mention current requirement: Android SDK + adb/emulator binaries.
- Clarify app may show first-run security warning if build is unsigned/not notarized.

## Handoff Prompt Stub (for another AI agent)
Build a modern, responsive marketing website for “EmuHub” using Next.js (App Router) and Tailwind CSS. Use this brief as the source of truth for product messaging, feature set, IA, and brand direction. Implement sections: Hero, Feature Grid, How It Works, Use Cases, Requirements, FAQ, and Final CTA. Use primary blue/purple gradients, keep visual style minimal and developer-focused, and optimize for conversion to GitHub Releases downloads.
