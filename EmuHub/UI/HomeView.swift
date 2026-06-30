//
//  HomeView.swift
//  EmuHub
//

import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var state: AppState
    let onNavigate: (AppRoute) -> Void
    @State private var avdSearch = ""
    @State private var searchActive = false

    private var filteredAVDs: [AVD] {
        guard !avdSearch.isEmpty else { return state.avds }
        return state.avds.filter {
            $0.friendlyName.localizedCaseInsensitiveContains(avdSearch) ||
            $0.name.localizedCaseInsensitiveContains(avdSearch)
        }
    }

    private func toggleSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            searchActive.toggle()
            if !searchActive { avdSearch = "" }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // Action success banner
                    if let action = state.lastAction {
                        ActionBanner(message: action)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Error banner
                    if let error = state.lastError {
                        ErrorBanner(message: error)
                            .padding(.horizontal, 14)
                            .padding(.top, state.lastAction == nil ? 12 : 4)
                            .padding(.bottom, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Running section
                    SectionHeader(
                        icon: "bolt.circle.fill", title: "Running",
                        color: .green, count: state.running.count,
                        buttons: []
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                    if state.running.isEmpty {
                        EmptyStateCard(icon: "moon.zzz", message: "No devices connected")
                            .padding(.horizontal, 14)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(state.running) { device in
                                RunningDeviceCard(
                                    device: device,
                                    isInstalling: state.installingAPK.contains(device.serial),
                                    onStop: { Task { await state.stop(device: device) } },
                                    onScreenshot: { Task { await state.captureScreenshot(device: device) } },
                                    onInstallAPK: { url in Task { await state.installAPK(device: device, url: url) } }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)

                    // Available AVDs section
                    SectionHeader(
                        icon: "square.stack.3d.up.fill", title: "Available",
                        color: .blue, count: state.avds.count,
                        buttons: state.avds.isEmpty ? [] : [
                            SectionHeaderButton(
                                id: "search", icon: "magnifyingglass",
                                help: "Search AVDs", active: searchActive,
                                action: toggleSearch
                            ),
                            SectionHeaderButton(
                                id: "create", icon: "plus",
                                help: "New AVD",
                                prominent: true,
                                action: { onNavigate(.createAVD) }
                            )
                        ]
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, searchActive ? 6 : 8)

                    // Search field — revealed by icon toggle
                    if searchActive {
                        AVDSearchField(text: $avdSearch, onDismiss: toggleSearch)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if state.avds.isEmpty {
                        EmptyStateCard(
                            icon: "square.dashed",
                            message: "No AVDs found",
                            detail: "Set your Android SDK path in Settings",
                            actionLabel: "Open Settings"
                        ) { onNavigate(.settings) }
                        .padding(.horizontal, 14)
                    } else if filteredAVDs.isEmpty {
                        EmptyStateCard(
                            icon: "magnifyingglass",
                            message: "No AVDs match \"\(avdSearch)\""
                        )
                        .padding(.horizontal, 14)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(filteredAVDs) { avd in
                                AVDCard(
                                    avd: avd,
                                    onStart:    { Task { await state.start(avd: avd) } },
                                    onColdBoot: { Task { await state.coldBoot(avd: avd) } },
                                    onWipeBoot: { Task { await state.wipeAndBoot(avd: avd) } },
                                    onDelete:   { Task { await state.deleteAVD(avd: avd) } }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    Spacer(minLength: 14)
                }
            }
            .animation(.easeOut(duration: 0.2), value: state.lastError != nil)
            .animation(.easeOut(duration: 0.2), value: state.lastAction != nil)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchActive)

            Divider().opacity(0.07)

            HomeFooter(
                isRefreshing: state.isRefreshing,
                lastRefresh: state.lastRefreshAt,
                onRefresh: { Task { await state.refreshAll() } }
            )
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color
    let count: Int
    var buttons: [SectionHeaderButton] = []

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            if count > 0 {
                CountBadge(count: count, tint: color)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 6)

            if !buttons.isEmpty {
                HStack(spacing: 6) {
                    ForEach(buttons) { btn in
                        SectionHeaderIconButton(button: btn, tint: color)
                    }
                }
            }
        }
        .animation(.spring(response: 0.3), value: count)
    }
}

/// A frosted-glass pill showing a section's item count, tinted to the section color.
private struct CountBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .monospacedDigit()
            .frame(minWidth: 11)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.75))
            )
            .contentTransition(.numericText())
    }
}

struct SectionHeaderButton: Identifiable {
    let id: String
    let icon: String
    let help: String
    var active: Bool = false
    /// Renders as a filled accent-gradient action (used for the primary "+" add button).
    var prominent: Bool = false
    let action: () -> Void
}

private struct SectionHeaderIconButton: View {
    let button: SectionHeaderButton
    let tint: Color
    @State private var hovered = false

    private var isOn: Bool { hovered || button.active }

    var body: some View {
        Button(action: button.action) {
            ZStack {
                if button.prominent {
                    Circle()
                        .fill(Accent.gradient(tint))
                        .shadow(color: tint.opacity(hovered ? 0.5 : 0.3),
                                radius: hovered ? 5 : 3, y: 1)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(tint.opacity(isOn ? 0.18 : 0.06)))
                        .overlay(Circle().strokeBorder(tint.opacity(isOn ? 0.4 : 0.14), lineWidth: 0.75))
                }

                Image(systemName: button.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(button.prominent
                        ? AnyShapeStyle(.white)
                        : AnyShapeStyle(isOn ? tint : tint.opacity(0.7)))
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .scaleEffect(hovered ? 1.1 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .help(button.help)
    }
}

// MARK: - AVD Search Field

private struct AVDSearchField: View {
    @Binding var text: String
    var onDismiss: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Filter AVDs…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)

            Button {
                if text.isEmpty {
                    onDismiss?()
                } else {
                    text = ""
                }
            } label: {
                Image(systemName: text.isEmpty ? "xmark" : "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            focused ? Color.blue.opacity(0.55) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: focused)
        .onAppear { focused = true }
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
                    Text(relativeTime(from: last))
                        .font(.system(size: 10.5))
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func relativeTime(from date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 5  { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        return "\(secs / 60)m ago"
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(
                        hovered ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07),
                        lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .opacity(isRefreshing ? 0.65 : 1)
        .onHover { hovered = $0 }
    }
}

