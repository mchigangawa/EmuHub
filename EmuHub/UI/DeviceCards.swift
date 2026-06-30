//
//  DeviceCards.swift
//  EmuHub
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Running Device Card

struct RunningDeviceCard: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice
    let isInstalling: Bool
    let onStop: () -> Void
    let onScreenshot: () -> Void
    let onInstallAPK: (URL) -> Void

    @State private var hovered = false
    @State private var isDropTargeted = false

    private var isRecording: Bool { state.recordingSerials.contains(device.serial) }
    private var isBusy: Bool { state.busyDevices.contains(device.serial) }
    private var accent: Color {
        device.hasIssue ? .orange : (device.isEmulator ? .green : .blue)
    }

    var body: some View {
        HStack(spacing: 12) {
            DeviceKindIcon(device: device, recording: isRecording)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(isRecording ? "Recording…" : device.statusDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(isRecording ? Color.red : (device.hasIssue ? Color.orange : .secondary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailingControls
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            CardSurface(tint: isRecording ? .red : accent, elevated: hovered)
                .overlay(
                    isDropTargeted
                        ? RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.blue, lineWidth: 2)
                        : nil
                )
        )
        // APK drop overlay
        .overlay(
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                                Text("Drop to Install APK")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        )
                }
            }
        )
        .onHover { hovered = $0 }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .contextMenu {
            if device.state == "device" {
                DeviceActionButtons(device: device, onScreenshot: onScreenshot, onStop: onStop)
                    .environmentObject(state)
            }
        }
        .help(device.isEmulator || device.state == "device"
              ? "Drop an .apk to install"
              : "")
    }

    /// Quick-access icon buttons only occupy space while hovering (or recording),
    /// so they never crowd the always-visible Stop button / status badge.
    private var showQuickActions: Bool { hovered || isRecording }

    @ViewBuilder
    private var trailingControls: some View {
        if isInstalling {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if device.state == "device" {
            HStack(spacing: 4) {
                if isBusy {
                    ProgressView().controlSize(.small).padding(.trailing, 2)
                }
                if showQuickActions {
                    ScreenshotButton(visible: true, action: onScreenshot)
                    RecordButton(isRecording: isRecording, visible: true) {
                        Task { await state.toggleScreenRecording(device: device) }
                    }
                }
                DeviceActionsMenu(device: device, onScreenshot: onScreenshot, onStop: onStop)
                    .environmentObject(state)
                if device.isEmulator {
                    StopButton(hovered: hovered, action: onStop)
                } else {
                    DeviceStatusBadge(device: device)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showQuickActions)
        } else {
            DeviceStatusBadge(device: device)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            } else {
                url = nil
            }
            guard let fileURL = url, fileURL.pathExtension.lowercased() == "apk" else { return }
            Task { @MainActor in onInstallAPK(fileURL) }
        }
        return true
    }
}

private struct DeviceKindIcon: View {
    let device: RunningDevice
    var recording: Bool = false

    var body: some View {
        GlassIconTile(systemImage: iconName, color: iconColor, size: 36)
            .overlay(alignment: .bottomTrailing) {
                if recording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
    }

    private var iconName: String {
        if device.hasIssue { return "exclamationmark.triangle.fill" }
        if device.isEmulator { return "play.fill" }
        return device.isTablet ? "ipad" : "iphone"
    }

    private var iconColor: Color {
        if device.hasIssue { return .orange }
        return device.isEmulator ? .green : .blue
    }
}

// MARK: - Record Button

private struct RecordButton: View {
    let isRecording: Bool
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isRecording ? Color.red : .secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isRecording ? Color.red.opacity(0.12)
                                                       : Color.secondary.opacity(visible ? 0.1 : 0)))
                .symbolEffect(.pulse, options: .repeating, isActive: isRecording)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: visible)
        .help(isRecording ? "Stop Recording" : "Record Screen")
    }
}

// MARK: - Device Actions Menu (ellipsis)

private struct DeviceActionsMenu: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice
    let onScreenshot: () -> Void
    let onStop: () -> Void
    @State private var hovered = false

    var body: some View {
        Menu {
            DeviceActionButtons(device: device, onScreenshot: onScreenshot, onStop: onStop)
                .environmentObject(state)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.secondary.opacity(hovered ? 0.12 : 0)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .help("Device actions")
    }
}

/// The shared set of action items, used by both the ellipsis menu and the
/// right-click context menu so they stay in sync.
private struct DeviceActionButtons: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice
    let onScreenshot: () -> Void
    let onStop: () -> Void

    private var isRecording: Bool { state.recordingSerials.contains(device.serial) }

    var body: some View {
        Button { onScreenshot() } label: {
            Label("Take Screenshot", systemImage: "camera")
        }
        Button { Task { await state.toggleScreenRecording(device: device) } } label: {
            Label(isRecording ? "Stop Recording" : "Record Screen",
                  systemImage: isRecording ? "stop.circle" : "record.circle")
        }

        Divider()

        Button { Task { await state.openShell(device: device) } } label: {
            Label("Open adb Shell", systemImage: "terminal")
        }
        Button { state.openAppManager(device: device) } label: {
            Label("Manage Apps…", systemImage: "square.grid.2x2")
        }
        Button { state.openLogcat(device: device) } label: {
            Label("View Logs…", systemImage: "doc.text.magnifyingglass")
        }

        Divider()

        Menu {
            ForEach(AdbService.RebootTarget.allCases, id: \.self) { target in
                Button {
                    Task { await state.reboot(device: device, target: target) }
                } label: {
                    Label(target.label, systemImage: target.systemImage)
                }
            }
        } label: {
            Label("Reboot", systemImage: "arrow.clockwise")
        }

        Divider()

        Button { state.copySerial(device: device) } label: {
            Label("Copy Serial", systemImage: "doc.on.doc")
        }
        if device.connectionType == .wifi {
            Button { state.copyAddress(device: device) } label: {
                Label("Copy Wi-Fi Address", systemImage: "wifi")
            }
        }

        if device.isEmulator {
            Divider()
            Button(role: .destructive) { onStop() } label: {
                Label("Stop Emulator", systemImage: "stop.fill")
            }
        }
    }
}

private struct ScreenshotButton: View {
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.secondary.opacity(visible ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: visible)
        .help("Take Screenshot")
    }
}

private struct StopButton: View {
    let hovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .semibold))
                if hovered {
                    Text("Stop")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, hovered ? 11 : 8)
            .padding(.vertical, 7)
            .background(Capsule().fill(hovered ? Color.red : Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hovered)
    }
}

private struct DeviceStatusBadge: View {
    let device: RunningDevice

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(badgeColor.opacity(0.1)))
    }

    private var label: String {
        if device.isUnauthorized { return "Unauthorized" }
        if device.isOffline { return "Offline" }
        return "Read-only"
    }

    private var badgeColor: Color {
        device.hasIssue ? .orange : .secondary
    }
}

// MARK: - AVD Card

struct AVDCard: View {
    let avd: AVD
    let onStart: () -> Void
    let onColdBoot: () -> Void
    let onWipeBoot: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            GlassIconTile(systemImage: avd.deviceType.systemImage,
                          color: avd.deviceType.color, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(avd.friendlyName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(avd.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            LaunchButton(hovered: hovered, color: avd.deviceType.color, action: onStart)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CardSurface(tint: avd.deviceType.color, elevated: hovered))
        .onHover { hovered = $0 }
        .contextMenu {
            Button {
                onStart()
            } label: {
                Label("Launch", systemImage: "play.fill")
            }

            Button {
                onColdBoot()
            } label: {
                Label("Cold Boot", systemImage: "snowflake")
            }

            Divider()

            Button(role: .destructive) {
                onWipeBoot()
            } label: {
                Label("Wipe Data & Boot", systemImage: "trash")
            }

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete AVD…", systemImage: "trash.slash")
            }
        }
        .confirmationDialog(
            "Delete “\(avd.friendlyName)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete AVD", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the virtual device and all of its data. This can't be undone.")
        }
    }
}

private struct LaunchButton: View {
    let hovered: Bool
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                if hovered {
                    Text("Launch")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, hovered ? 11 : 8)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(hovered ? color : color.opacity(0.7))
                    .shadow(color: hovered ? color.opacity(0.3) : .clear, radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hovered)
    }
}

// MARK: - Shared Card Background

private struct CardSurface: View {
    var tint: Color? = nil
    var elevated: Bool = false
    var body: some View {
        GlassCard(cornerRadius: 12, tint: tint, elevated: elevated)
    }
}

