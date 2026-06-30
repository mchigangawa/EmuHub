//
//  SettingsView.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var preferredWidth: CGFloat? = 560

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                generalSection
                sdkSection
                emulatorSection
                refreshSection
            }
            .padding(20)
        }
        .frame(width: preferredWidth)
        .onAppear { state.refreshLaunchAtLoginState() }
    }

    // MARK: - General

    private var generalSection: some View {
        PrefsSection(title: "General") {
            PrefsRow(
                icon: "arrow.circlepath",
                iconColor: .blue,
                title: "Launch at Login",
                description: "Start EmuHub automatically when you log in"
            ) {
                Toggle("", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .disabled(state.launchAtLoginError != nil && !state.launchAtLoginEnabled)
            }

            if let err = state.launchAtLoginError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - SDK

    private var sdkSection: some View {
        PrefsSection(title: "Android SDK") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("SDK Path")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Auto-detect") {
                            let path = AndroidToolchain.defaultMacSdkPath()
                            state.sdkPath = path
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 11))
                    }
                    TextField("~/Library/Android/sdk", text: $state.sdkPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .glassField()
                    Text("Root folder containing platform-tools, emulator, and avd directories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Emulator

    private var emulatorSection: some View {
        PrefsSection(title: "Emulator") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Extra Launch Arguments")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Reset") {
                        state.emulatorExtraArgs = "-no-snapshot-load"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11))
                }
                TextField("-no-snapshot-load -gpu host", text: $state.emulatorExtraArgs)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .glassField()
                Text("Flags passed to the emulator binary at launch. Separate multiple flags with spaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Common: -no-snapshot-load · -gpu host · -no-audio · -wipe-data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
            .padding(16)
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        PrefsSection(title: "Refresh") {
            VStack(spacing: 0) {
                PrefsRow(
                    icon: "clock.arrow.circlepath",
                    iconColor: .purple,
                    title: "Auto-refresh interval",
                    description: "How often EmuHub polls adb for changes"
                ) {
                    Text("Every \(Int(state.autoRefreshSeconds))s")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 60, alignment: .trailing)
                }

                VStack(spacing: 4) {
                    Slider(value: $state.autoRefreshSeconds, in: 3...60, step: 1)
                        .tint(.purple)
                    HStack {
                        Text("3s")
                        Spacer()
                        Text("30s")
                        Spacer()
                        Text("60s")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                Divider().padding(.horizontal, 16)

                HStack {
                    Button {
                        Task { await state.refreshAll() }
                    } label: {
                        HStack(spacing: 6) {
                            if state.isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(state.isRefreshing ? "Refreshing…" : "Refresh Now")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(state.isRefreshing)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Spacer()

                    if let last = state.lastRefreshAt {
                        TimelineView(.periodic(from: .now, by: 10)) { _ in
                            Text("Last: \(relativeTime(from: last))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.trailing, 16)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { state.launchAtLoginEnabled },
            set: { state.setLaunchAtLogin($0) }
        )
    }

    private func relativeTime(from date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 5  { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        return "\(secs / 60)m ago"
    }
}

// MARK: - Reusable Components

private struct PrefsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            GlassGroup(cornerRadius: 12) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrefsRow<Accessory: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var description: String? = nil
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            GlassIconTile(systemImage: icon, color: iconColor, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let desc = description {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
