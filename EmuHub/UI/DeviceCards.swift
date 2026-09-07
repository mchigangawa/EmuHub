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
    /// An APK install or file push is in flight for this device.
    let isTransferring: Bool
    let onStop: () -> Void
    let onScreenshot: () -> Void
    let onDropFile: (URL) -> Void

    @State private var hovered = false
    @State private var isDropTargeted = false

    private var isRecording: Bool { state.recordingSerials.contains(device.serial) }
    private var isBusy: Bool { state.busyDevices.contains(device.serial) }
    private var isReady: Bool { device.state == "device" }

    private var accent: Color {
        if device.hasIssue { return Theme.Palette.warning }
        return device.isEmulator ? Theme.Palette.emulator : Theme.Palette.physical
    }

    var body: some View {
        HStack(spacing: Theme.Space.lg) {
            DeviceKindIcon(device: device, recording: isRecording)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.ehCaption)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.md)

            trailingControls
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, 10)
        .background(
            GlassCard(
                cornerRadius: Theme.Radius.md,
                tint: isRecording ? Theme.Palette.danger : accent,
                elevated: hovered
            )
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.accent, lineWidth: 2)
                }
            }
        )
        .overlay { dropOverlay }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onTapGesture(count: 2) {
            guard isReady else { return }
            state.openInspector(device: device)
        }
        .contextMenu {
            if isReady {
                DeviceActionButtons(device: device, onScreenshot: onScreenshot, onStop: onStop)
                    .environmentObject(state)
            }
        }
        .tooltip(isReady ? "Double-click for details · drop a file to install or push" : "")
        .animation(Theme.Motion.snappy, value: hovered)
    }

    private var subtitle: String {
        if isRecording { return "Recording…" }
        if isTransferring { return "Transferring…" }
        return device.statusDescription
    }

    private var subtitleColor: Color {
        if isRecording { return Theme.Palette.danger }
        return device.hasIssue ? Theme.Palette.warning : .secondary
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    VStack(spacing: Theme.Space.xs) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.Palette.accent)
                        Text("Drop to install or push")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                }
        }
    }

    /// Quick-access icon buttons only occupy space while hovering (or recording),
    /// so they never crowd the always-visible Stop button / status badge.
    private var showQuickActions: Bool { hovered || isRecording }

    @ViewBuilder
    private var trailingControls: some View {
        if isTransferring {
            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small)
                Text("Sending…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if isReady {
            HStack(spacing: Theme.Space.xs) {
                if isBusy {
                    ProgressView().controlSize(.small).padding(.trailing, 2)
                }

                if showQuickActions {
                    IconButton(systemImage: "camera.fill", help: "Take Screenshot",
                               size: Theme.Size.iconButton, symbolSize: 11, action: onScreenshot)
                        .transition(.opacity)

                    IconButton(
                        systemImage: isRecording ? "stop.circle.fill" : "record.circle",
                        help: isRecording ? "Stop Recording" : "Record Screen",
                        style: isRecording ? .danger : .plain,
                        size: Theme.Size.iconButton,
                        symbolSize: 13,
                        isActive: isRecording
                    ) {
                        Task { await state.toggleScreenRecording(device: device) }
                    }
                    .transition(.opacity)

                    IconButton(systemImage: "info.circle", help: "Device Details",
                               size: Theme.Size.iconButton, symbolSize: 12) {
                        state.openInspector(device: device)
                    }
                    .transition(.opacity)
                }

                DeviceActionsMenu(device: device, onScreenshot: onScreenshot, onStop: onStop)
                    .environmentObject(state)

                if device.isEmulator {
                    ExpandingPill(
                        systemImage: "stop.fill",
                        label: "Stop",
                        tint: Theme.Palette.danger,
                        style: .quiet,
                        expanded: hovered,
                        action: onStop
                    )
                } else {
                    DeviceStatusBadge(device: device)
                }
            }
            .animation(Theme.Motion.snappy, value: showQuickActions)
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
            // Anything is accepted now: APKs install, everything else is pushed
            // to the device's Download folder.
            guard let fileURL = url else { return }
            Task { @MainActor in onDropFile(fileURL) }
        }
        return true
    }
}

private struct DeviceKindIcon: View {
    let device: RunningDevice
    var recording: Bool = false

    var body: some View {
        GlassIconTile(systemImage: iconName, color: iconColor, size: Theme.Size.avatar)
            .overlay(alignment: .bottomTrailing) {
                if recording {
                    Circle()
                        .fill(Theme.Palette.danger)
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
        if device.hasIssue { return Theme.Palette.warning }
        return device.isEmulator ? Theme.Palette.emulator : Theme.Palette.physical
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
                .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
                .background(Circle().fill(Color.primary.opacity(hovered ? 0.10 : 0.05)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .animation(Theme.Motion.snappy, value: hovered)
        .tooltip("Device actions")
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
        Button { state.openInspector(device: device) } label: {
            Label("Device Details…", systemImage: "info.circle")
        }

        Divider()

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
        Button { Task { await state.pasteClipboard(device: device) } } label: {
            Label("Send Mac Clipboard", systemImage: "doc.on.clipboard")
        }

        Divider()

        Menu {
            ForEach(AdbService.KeyEvent.allCases, id: \.self) { key in
                Button { Task { await state.sendKey(device: device, key: key) } } label: {
                    Label(key.label, systemImage: key.systemImage)
                }
            }
        } label: {
            Label("Send Key", systemImage: "keyboard")
        }

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

        // Wireless options only make sense for physical devices — an emulator is
        // already reachable and `tcpip` would just break its connection.
        if !device.isEmulator {
            Divider()
            if device.connectionType == .usb {
                Button { Task { await state.enableWirelessDebugging(device: device) } } label: {
                    Label("Switch to Wi-Fi…", systemImage: "wifi")
                }
            } else {
                Button { Task { await state.disconnectWireless(device: device) } } label: {
                    Label("Disconnect Wi-Fi", systemImage: "wifi.slash")
                }
            }
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

private struct DeviceStatusBadge: View {
    let device: RunningDevice

    var body: some View {
        HStack(spacing: 5) {
            if !device.hasIssue {
                Image(systemName: device.connectionType == .wifi ? "wifi" : "cable.connector")
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(badgeColor.opacity(0.12)))
    }

    private var label: String {
        if device.isUnauthorized { return "Unauthorized" }
        if device.isOffline { return "Offline" }
        return device.connectionType == .wifi ? "Wi-Fi" : "USB"
    }

    private var badgeColor: Color {
        device.hasIssue ? Theme.Palette.warning : .secondary
    }
}

// MARK: - AVD Card

struct AVDCard: View {
    let avd: AVD
    /// This AVD already has a live emulator, so launching again would only error.
    var isRunning: Bool = false
    /// Launch requested; the emulator hasn't registered with adb yet.
    var isBooting: Bool = false
    let onStart: () -> Void
    let onColdBoot: () -> Void
    let onWipeBoot: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false
    @State private var confirmingDelete = false

    private var isActive: Bool { isRunning || isBooting }

    var body: some View {
        HStack(spacing: Theme.Space.lg) {
            GlassIconTile(
                systemImage: avd.deviceType.systemImage,
                color: avd.deviceType.color,
                size: Theme.Size.avatar
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(avd.friendlyName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(avd.subtitle)
                    .font(.ehCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Space.md)

            if isActive {
                RunningBadge(booting: isBooting)
            } else {
                ExpandingPill(
                    systemImage: "play.fill",
                    label: "Launch",
                    tint: avd.deviceType.color,
                    style: .filled,
                    expanded: hovered,
                    action: onStart
                )
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, 10)
        .background(GlassCard(
            cornerRadius: Theme.Radius.md,
            tint: avd.deviceType.color,
            elevated: hovered
        ))
        // A running AVD is shown for reference, so it recedes rather than
        // competing with the ones you can actually launch.
        .opacity(isActive ? 0.65 : 1)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.snappy, value: hovered)
        .contextMenu {
            Button(action: onStart) {
                Label("Launch", systemImage: "play.fill")
            }
            .disabled(isActive)

            Button(action: onColdBoot) {
                Label("Cold Boot", systemImage: "snowflake")
            }
            .disabled(isActive)

            Divider()

            Button(role: .destructive, action: onWipeBoot) {
                Label("Wipe Data & Boot", systemImage: "trash")
            }
            .disabled(isActive)

            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete AVD…", systemImage: "trash.slash")
            }
            .disabled(isActive)
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

/// Badge shown in place of Launch when an AVD is already up (or coming up).
private struct RunningBadge: View {
    let booting: Bool

    var body: some View {
        HStack(spacing: 5) {
            if booting {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            } else {
                StatusDot(color: Theme.Palette.emulator, size: 5)
            }
            Text(booting ? "Starting" : "Running")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.Palette.emulator.opacity(0.12)))
    }
}
