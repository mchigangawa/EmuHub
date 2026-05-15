//
//  HelpView.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import SwiftUI

// MARK: - Data Models

private struct HelpItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

private struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let items: [HelpItem]
}

private let helpSections: [HelpSection] = [
    HelpSection(
        icon: "play.circle.fill",
        iconColor: .green,
        title: "Getting Started",
        items: [
            HelpItem(
                question: "How do I start an emulator?",
                answer: "Click the EmuHub icon in your macOS menu bar. Under the Available section you'll see your Android Virtual Devices (AVDs). Click any AVD's Launch button. The emulator will appear in the Running section once it's active."
            ),
            HelpItem(
                question: "What are Cold Boot and Wipe & Boot?",
                answer: "Right-click (or long-press) any AVD card to see launch options. Cold Boot skips the saved snapshot and performs a full restart — useful when the emulator is stuck. Wipe & Boot clears all user data and resets the device to its factory state before booting."
            ),
            HelpItem(
                question: "How do I stop a running emulator?",
                answer: "In the Running section, hover over the emulator row and click the Stop button that appears. EmuHub sends an adb emu kill command to cleanly terminate the process."
            ),
            HelpItem(
                question: "Why don't I see any AVDs in the menu?",
                answer: "EmuHub needs a valid Android SDK path to detect your AVDs. Open Settings and verify the SDK Path is correct. The default location is ~/Library/Android/sdk. Tap Auto-detect to have EmuHub try to find it automatically, then use Refresh Now to reload the list."
            ),
            HelpItem(
                question: "How do I search for a specific AVD?",
                answer: "Click the magnifying glass icon in the Available section header to reveal the search field. Type any part of the AVD name to filter the list. Press Escape or click the icon again to dismiss the search."
            ),
            HelpItem(
                question: "How do I create a new AVD?",
                answer: "Click the + icon in the Available section header to open the New AVD screen. Enter a name, choose a system image package, and select a device profile, then tap Create. EmuHub runs avdmanager in the background — the new AVD appears in the list once creation completes."
            ),
        ]
    ),
    HelpSection(
        icon: "cpu.fill",
        iconColor: .indigo,
        title: "Device Actions",
        items: [
            HelpItem(
                question: "How do I take a screenshot?",
                answer: "Hover over a running device or emulator in the Running section and click the camera icon. EmuHub captures the screen via adb, saves the PNG to your Desktop, and reveals it in Finder automatically."
            ),
            HelpItem(
                question: "How do I install an APK?",
                answer: "Drag an APK file from Finder and drop it onto any running device or emulator row in the Running section. A progress indicator appears while adb installs the package. You'll see a success banner when it's done, or an error message if the install fails."
            ),
            HelpItem(
                question: "Can I control physical Android devices through EmuHub?",
                answer: "Physical devices appear in the Running section for visibility. Screenshot and APK install work on physical devices just like emulators. However, Start and Stop actions are emulator-only — EmuHub won't send power commands to real hardware."
            ),
        ]
    ),
    HelpSection(
        icon: "wrench.and.screwdriver.fill",
        iconColor: .orange,
        title: "Troubleshooting",
        items: [
            HelpItem(
                question: "EmuHub can't find my Android SDK",
                answer: "EmuHub tries to auto-detect your SDK at ~/Library/Android/sdk. If you installed Android Studio to a custom location, open Settings → Android SDK and enter the correct path manually. The path should point to the root sdk folder that contains platform-tools, emulator, and avd subdirectories."
            ),
            HelpItem(
                question: "My physical device shows as 'Unauthorized'",
                answer: "This means USB debugging hasn't been approved for this Mac. Unlock your device and look for the 'Allow USB Debugging?' prompt on screen, then tap Allow. If the prompt doesn't appear, try unplugging and replugging the cable. Make sure USB debugging is enabled in Developer Options."
            ),
            HelpItem(
                question: "My physical device shows as 'Offline'",
                answer: "The device is connected but adb can't communicate with it. Try unplugging and replugging the cable, or run adb kill-server && adb start-server in Terminal to reset the adb daemon. Also check that your USB cable supports data transfer, not just charging."
            ),
            HelpItem(
                question: "The device list isn't updating",
                answer: "Use Refresh Now in Settings to force an immediate update, or lower the auto-refresh interval. If the issue persists, check that adb is accessible — EmuHub uses the adb binary inside your SDK's platform-tools folder."
            ),
            HelpItem(
                question: "New AVD creation fails",
                answer: "AVD creation requires avdmanager, which ships with Android Command-line Tools (not just the emulator package). Open Android Studio's SDK Manager, go to SDK Tools, and make sure Android SDK Command-line Tools is installed. Then verify your SDK Path in EmuHub Settings points to the correct root folder."
            ),
            HelpItem(
                question: "macOS says EmuHub can't be opened",
                answer: "EmuHub is signed with an Apple Personal Team certificate and is not notarized. To open it: right-click EmuHub.app → Open → Open. Alternatively, go to System Settings → Privacy & Security and click Open Anyway. You only need to do this once."
            ),
        ]
    ),
    HelpSection(
        icon: "gearshape.fill",
        iconColor: .blue,
        title: "Configuration",
        items: [
            HelpItem(
                question: "What are Extra Launch Arguments?",
                answer: "Extra Args are additional command-line flags passed to the emulator at launch. Common examples: -no-snapshot-load to always cold-boot, -gpu host to use your Mac's GPU, -no-audio to disable audio, -wipe-data to reset user data. Separate multiple flags with spaces."
            ),
            HelpItem(
                question: "How does auto-refresh work?",
                answer: "EmuHub polls adb at a regular interval to detect changes in emulator and device state. You can configure the interval between 3 and 60 seconds in Settings → Refresh. A shorter interval means faster updates but slightly more CPU usage."
            ),
            HelpItem(
                question: "How do I make EmuHub launch at login?",
                answer: "Open Settings → General and toggle on Launch at Login. EmuHub uses the macOS ServiceManagement API to register as a login item — no third-party helpers needed. This requires macOS 13 or later."
            ),
            HelpItem(
                question: "How do I update EmuHub?",
                answer: "Open the hamburger menu (≡) and tap Software Update. EmuHub checks GitHub Releases for a newer version. If one is available, click Install Update — EmuHub downloads the release zip, swaps the app bundle in-place, and relaunches automatically."
            ),
        ]
    ),
]

// MARK: - Main View

struct HelpView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                ForEach(helpSections) { section in
                    HelpSectionView(section: section)
                }
                SupportLinksView()
            }
            .padding(16)
        }
    }
}

// MARK: - Section

private struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(section.iconColor.opacity(0.12))
                        .frame(width: 20, height: 20)
                    Image(systemName: section.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(section.iconColor)
                }
                Text(section.title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
            }

            // Accordion items
            VStack(spacing: 1) {
                ForEach(section.items) { item in
                    HelpAccordionRow(item: item)
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Accordion Row

private struct HelpAccordionRow: View {
    let item: HelpItem
    @State private var expanded = false
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Text(item.question)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: expanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .background(hovered && !expanded ? Color.primary.opacity(0.035) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }

            if expanded {
                Divider().padding(.horizontal, 16)

                Text(item.answer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Support Links

private struct SupportLinksView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 20, height: 20)
                    Image(systemName: "ellipsis.bubble.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                Text("Still Need Help?".uppercased())
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
            }

            VStack(spacing: 1) {
                SupportLinkRow(
                    icon: "ladybug.fill",
                    iconColor: .red,
                    label: "Report a Bug",
                    subtitle: "Open a GitHub issue",
                    url: "https://github.com/mchigangawa/EmuHub/issues/new"
                )
                Divider().padding(.leading, 44)
                SupportLinkRow(
                    icon: "lightbulb.fill",
                    iconColor: .yellow,
                    label: "Request a Feature",
                    subtitle: "Share your ideas on GitHub",
                    url: "https://github.com/mchigangawa/EmuHub/issues/new"
                )
                Divider().padding(.leading, 44)
                SupportLinkRow(
                    icon: "doc.text.fill",
                    iconColor: .blue,
                    label: "View Changelog",
                    subtitle: "See what's new in each release",
                    url: "https://github.com/mchigangawa/EmuHub/blob/main/CHANGELOG.md"
                )
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SupportLinkRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let subtitle: String
    let url: String
    @State private var hovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(hovered ? Color.primary.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
