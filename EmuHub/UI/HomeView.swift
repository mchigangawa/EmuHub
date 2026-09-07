//
//  HomeView.swift
//  EmuHub
//

import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var state: AppState
    let onNavigate: (AppRoute) -> Void

    @State private var search = ""

    /// One search box filters both sections — previously only AVDs were
    /// searchable, which meant the box did nothing when the thing you were
    /// looking for was an attached device.
    private var filteredDevices: [RunningDevice] {
        guard !search.isEmpty else { return state.running }
        return state.running.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
            $0.serial.localizedCaseInsensitiveContains(search)
        }
    }

    private var filteredAVDs: [AVD] {
        guard !search.isEmpty else { return state.avds }
        return state.avds.filter {
            $0.friendlyName.localizedCaseInsensitiveContains(search) ||
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    /// AVDs we've launched that haven't registered with adb yet, shown as
    /// placeholder rows in Running so a launch never looks like it did nothing.
    private var bootingAVDs: [AVD] {
        state.avds.filter { state.bootingAVDs.contains($0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HomeToolbar(
                search: $search,
                onConnectDevice: { state.openWirelessSheet() },
                onNewAVD: { onNavigate(.createAVD) }
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    banners

                    runningSection

                    Hairline()
                        .padding(.vertical, Theme.Space.xl)

                    availableSection

                    Spacer(minLength: Theme.Space.gutter)
                }
            }
            .animation(Theme.Motion.fade, value: state.lastError != nil)
            .animation(Theme.Motion.fade, value: state.lastAction != nil)
            .animation(Theme.Motion.smooth, value: state.running)
            .animation(Theme.Motion.smooth, value: state.bootingAVDs)

            Hairline(inset: 0).opacity(0.6)

            HomeFooter(
                isRefreshing: state.isRefreshing,
                lastRefresh: state.lastRefreshAt,
                onRefresh: { Task { await state.refreshAll() } }
            )
        }
    }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        if let action = state.lastAction {
            ActionBanner(message: action)
                .pageGutter()
                .padding(.top, Theme.Space.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        if let error = state.lastError {
            ErrorBanner(message: error) { state.lastError = nil }
                .pageGutter()
                .padding(.top, state.lastAction == nil ? Theme.Space.lg : Theme.Space.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Running

    private var runningSection: some View {
        VStack(spacing: 0) {
            SectionHeader(
                icon: "bolt.circle.fill",
                title: "Running",
                color: Theme.Palette.emulator,
                count: state.running.count
            )
            .pageGutter()
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.md)

            if state.running.isEmpty && bootingAVDs.isEmpty {
                EmptyStateCard(
                    icon: "moon.zzz",
                    message: "No devices connected",
                    detail: "Launch an AVD below, plug in a phone, or connect one over Wi-Fi."
                )
                .pageGutter()
            } else if filteredDevices.isEmpty && bootingAVDs.isEmpty {
                EmptyStateCard(icon: "magnifyingglass", message: "No devices match “\(search)”")
                    .pageGutter()
            } else {
                VStack(spacing: Theme.Space.rowGap) {
                    ForEach(bootingAVDs) { avd in
                        BootingCard(avd: avd)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }

                    ForEach(filteredDevices) { device in
                        RunningDeviceCard(
                            device: device,
                            isTransferring: state.installingAPK.contains(device.serial),
                            onStop: { Task { await state.stop(device: device) } },
                            onScreenshot: { Task { await state.captureScreenshot(device: device) } },
                            onDropFile: { url in Task { await state.handleDroppedFile(device: device, url: url) } }
                        )
                    }
                }
                .pageGutter()
            }
        }
    }

    // MARK: Available

    private var availableSection: some View {
        VStack(spacing: 0) {
            SectionHeader(
                icon: "square.stack.3d.up.fill",
                title: "Available",
                color: Theme.Palette.physical,
                count: state.avds.count
            )
            .pageGutter()
            .padding(.bottom, Theme.Space.md)

            if state.avds.isEmpty {
                EmptyStateCard(
                    icon: "square.dashed",
                    message: "No AVDs found",
                    detail: "Set your Android SDK path in Settings, or create your first virtual device.",
                    actionLabel: "Open Settings"
                ) { onNavigate(.settings) }
                .pageGutter()
            } else if filteredAVDs.isEmpty {
                EmptyStateCard(icon: "magnifyingglass", message: "No AVDs match “\(search)”")
                    .pageGutter()
            } else {
                VStack(spacing: Theme.Space.rowGap) {
                    ForEach(filteredAVDs) { avd in
                        AVDCard(
                            avd: avd,
                            isRunning: state.runningAVDNames.contains(avd.name),
                            isBooting: state.bootingAVDs.contains(avd.name),
                            onStart:    { Task { await state.start(avd: avd) } },
                            onColdBoot: { Task { await state.coldBoot(avd: avd) } },
                            onWipeBoot: { Task { await state.wipeAndBoot(avd: avd) } },
                            onDelete:   { Task { await state.deleteAVD(avd: avd) } }
                        )
                    }
                }
                .pageGutter()
            }
        }
    }
}

// MARK: - Toolbar

/// A persistent strip under the nav bar holding search and the page's two
/// creation actions. Giving these a fixed home means they no longer hide inside
/// section headers, and search no longer has to be revealed before it can be used.
private struct HomeToolbar: View {
    @Binding var search: String
    let onConnectDevice: () -> Void
    let onNewAVD: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            SearchField(
                text: $search,
                placeholder: "Search devices and AVDs…",
                shape: .capsule
            )

            IconButton(
                systemImage: "wifi",
                help: "Connect a device over Wi-Fi",
                style: .tinted(Theme.Palette.physical),
                size: Theme.Size.iconButton,
                symbolSize: 12,
                action: onConnectDevice
            )

            IconButton(
                systemImage: "plus",
                help: "New AVD",
                style: .prominent(Theme.Palette.physical),
                size: Theme.Size.iconButton,
                symbolSize: 12,
                action: onNewAVD
            )
        }
        .pageGutter()
        .padding(.vertical, Theme.Space.md)
    }
}

// MARK: - Booting Placeholder

/// Stand-in row shown between "Launch" and the emulator appearing in `adb devices`.
private struct BootingCard: View {
    let avd: AVD

    var body: some View {
        HStack(spacing: Theme.Space.lg) {
            GlassIconTile(
                systemImage: avd.deviceType.systemImage,
                color: avd.deviceType.color,
                size: Theme.Size.avatar
            )
            .opacity(0.7)

            VStack(alignment: .leading, spacing: 3) {
                Text(avd.friendlyName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("Starting…")
                    .font(.ehCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Space.md)

            ProgressView().controlSize(.small)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, 10)
        .background(GlassCard(cornerRadius: Theme.Radius.md, tint: avd.deviceType.color))
        .opacity(0.85)
    }
}

// MARK: - Home Footer

private struct HomeFooter: View {
    let isRefreshing: Bool
    let lastRefresh: Date?
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RefreshButton(isRefreshing: isRefreshing, action: onRefresh)

            Spacer()

            if let last = lastRefresh {
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    Text(RelativeTime.string(from: last))
                        .font(.ehFootnote)
                        .foregroundStyle(.quaternary)
                        .monospacedDigit()
                }
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.leading, Theme.Space.gutter)
        // The popover's resize grip lives in this corner, so the footer stops
        // short of it rather than putting Quit under the drag target.
        .padding(.trailing, Theme.Space.xxl)
        .padding(.vertical, 10)
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
                Text(isRefreshing ? "Refreshing…" : "Refresh")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(hovered ? .primary : .secondary)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(
                        Color.primary.opacity(hovered ? 0.14 : 0.07),
                        lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .opacity(isRefreshing ? 0.65 : 1)
        .onHover { hovered = $0 }
        .keyboardShortcut("r", modifiers: .command)
        .help("Refresh device list (⌘R)")
    }
}

// MARK: - Relative Time

/// Shared by the Home footer and the Settings page, which had grown separate
/// copies of the same formatting.
enum RelativeTime {
    static func string(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}
