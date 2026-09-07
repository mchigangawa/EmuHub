//
//  DeviceInspectorView.swift
//  EmuHub
//
//  A live read-out of one device — battery, storage, display, OS, network —
//  plus the developer actions that are tedious to type by hand: rotation, dark
//  mode, deep links, clipboard send, and navigation keys.
//

import SwiftUI

struct DeviceInspectorView: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice

    @State private var deepLink = ""
    @State private var textToSend = ""

    private var accent: Color {
        device.isEmulator ? Theme.Palette.emulator : Theme.Palette.physical
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                icon: "waveform.path.ecg.rectangle",
                tint: accent,
                title: "Device Details",
                subtitle: device.displayName,
                onClose: { state.closeInspector() }
            ) {
                IconButton(
                    systemImage: "arrow.clockwise",
                    help: "Reload details",
                    size: 24,
                    symbolSize: 11
                ) {
                    Task { await state.loadDeviceInfo(for: device) }
                }
                .opacity(state.isLoadingDeviceInfo ? 0.4 : 1)
                .disabled(state.isLoadingDeviceInfo)
            }

            Hairline(inset: 0).opacity(0.5)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Space.xl) {
                    if state.isLoadingDeviceInfo && state.deviceInfo == nil {
                        PanelMessage(showsProgress: true, message: "Reading device details…")
                            .frame(height: 180)
                    } else if let error = state.deviceInfoError, state.deviceInfo == nil {
                        PanelMessage(
                            systemImage: "exclamationmark.triangle",
                            message: error,
                            tint: Theme.Palette.warning
                        )
                        .frame(height: 180)
                    } else {
                        statusSection
                        detailsSection
                    }

                    actionsSection
                    inputSection
                    navigationSection
                }
                .padding(Theme.Space.gutter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground(tint: accent) }
    }

    // MARK: - Status Meters

    /// Battery and storage get meters rather than plain rows — they're the two
    /// values you scan for rather than read.
    private var statusSection: some View {
        HStack(spacing: Theme.Space.md) {
            if let info = state.deviceInfo {
                MeterTile(
                    icon: info.batteryStatus?.systemImage ?? "battery.50",
                    label: "Battery",
                    value: info.batteryText ?? "—",
                    detail: info.temperatureText,
                    fraction: info.batteryLevel.map { Double($0) / 100 },
                    tint: batteryTint(for: info)
                )

                MeterTile(
                    icon: "internaldrive",
                    label: "Storage",
                    value: storageHeadline(for: info),
                    detail: info.storageText,
                    fraction: info.storageFraction,
                    tint: (info.storageFraction ?? 0) > 0.9 ? Theme.Palette.warning : Theme.Palette.physical
                )
            }
        }
    }

    private func batteryTint(for info: DeviceInfo) -> Color {
        if info.batteryStatus == .charging || info.batteryStatus == .full { return Theme.Palette.emulator }
        guard let level = info.batteryLevel else { return Theme.Palette.neutral }
        if level <= 15 { return Theme.Palette.danger }
        if level <= 30 { return Theme.Palette.warning }
        return Theme.Palette.emulator
    }

    private func storageHeadline(for info: DeviceInfo) -> String {
        guard let fraction = info.storageFraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))% used"
    }

    // MARK: - Detail Rows

    private var detailsSection: some View {
        InspectorSection(title: "About") {
            if let info = state.deviceInfo {
                DetailRow(icon: "cpu", label: "Hardware", value: info.hardwareText)
                DetailRow(icon: "shippingbox", label: "OS", value: info.osText)
                DetailRow(icon: "rectangle.on.rectangle", label: "Display", value: info.resolutionText)
                DetailRow(icon: "clock", label: "Uptime", value: info.uptimeText)
                DetailRow(
                    icon: device.connectionType == .wifi ? "wifi" : "cable.connector",
                    label: "Connection",
                    value: device.connectionType == .wifi ? "Wi-Fi" : "USB"
                )
                DetailRow(icon: "network", label: "IP Address", value: info.ipAddress, copyable: true)
                DetailRow(icon: "number", label: "Serial", value: device.serial, copyable: true, last: true)
            }
        }
    }

    // MARK: - Toggles & Rotation

    private var actionsSection: some View {
        InspectorSection(title: "Appearance & Orientation") {
            HStack(spacing: Theme.Space.lg) {
                GlassIconTile(systemImage: "moon.stars", color: .indigo, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dark Mode")
                        .font(.ehBody)
                    Text(darkModeSubtitle)
                        .font(.ehCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: darkModeBinding)
                    .labelsHidden()
                    .disabled(state.isDarkModeOn == nil)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 11)

            Hairline(inset: Theme.Space.lg)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Rotation")
                    .font(.ehBody)

                HStack(spacing: Theme.Space.sm) {
                    ForEach(AdbService.Rotation.allCases, id: \.self) { rotation in
                        ChipButton(
                            systemImage: rotation.systemImage,
                            label: shortRotationLabel(rotation),
                            tint: accent
                        ) {
                            Task { await state.setRotation(device: device, rotation: rotation) }
                        }
                    }

                    ChipButton(systemImage: "arrow.triangle.2.circlepath", label: "Auto", tint: accent) {
                        Task { await state.enableAutoRotate(device: device) }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.lg)
        }
    }

    private func shortRotationLabel(_ rotation: AdbService.Rotation) -> String {
        switch rotation {
        case .portrait:           "Portrait"
        case .landscape:          "Landscape"
        case .portraitUpsideDown: "Flipped"
        case .landscapeReversed:  "Reversed"
        }
    }

    private var darkModeSubtitle: String {
        switch state.isDarkModeOn {
        case .some(true):  "Device is in dark mode"
        case .some(false): "Device is in light mode"
        case .none:        "Not reported by this device"
        }
    }

    private var darkModeBinding: Binding<Bool> {
        Binding(
            get: { state.isDarkModeOn ?? false },
            set: { _ in Task { await state.toggleDarkMode(device: device) } }
        )
    }

    // MARK: - Deep Link & Text Input

    private var inputSection: some View {
        InspectorSection(title: "Send to Device") {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                FieldLabel(icon: "link", text: "Open URL or deep link")
                HStack(spacing: Theme.Space.sm) {
                    TextField("https://example.com or myapp://path", text: $deepLink)
                        .textFieldStyle(.plain)
                        .font(.ehMonoSmall)
                        .glassField()
                        .onSubmit(sendDeepLink)

                    SendButton(tint: accent, disabled: deepLink.trimmed.isEmpty, action: sendDeepLink)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.lg)

            Hairline(inset: Theme.Space.lg)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                FieldLabel(icon: "keyboard", text: "Type text into the focused field")
                HStack(spacing: Theme.Space.sm) {
                    TextField("Text to type…", text: $textToSend)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .glassField()
                        .onSubmit(sendText)

                    SendButton(tint: accent, disabled: textToSend.isEmpty, action: sendText)
                }

                Button {
                    Task { await state.pasteClipboard(device: device) }
                } label: {
                    Label("Send Mac clipboard", systemImage: "doc.on.clipboard")
                        .font(.ehCaption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .padding(.top, Theme.Space.xxs)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.lg)
        }
    }

    private func sendDeepLink() {
        let url = deepLink.trimmed
        guard !url.isEmpty else { return }
        Task {
            await state.openURL(device: device, url: url)
            if state.lastError == nil { deepLink = "" }
        }
    }

    private func sendText() {
        let text = textToSend
        guard !text.isEmpty else { return }
        Task {
            await state.sendText(device: device, text: text)
            if state.lastError == nil { textToSend = "" }
        }
    }

    // MARK: - Navigation Keys

    private var navigationSection: some View {
        InspectorSection(title: "Keys") {
            HStack(spacing: Theme.Space.sm) {
                ForEach(AdbService.KeyEvent.allCases, id: \.self) { key in
                    IconButton(
                        systemImage: key.systemImage,
                        help: key.label,
                        style: .tinted(accent),
                        size: 30,
                        symbolSize: 12
                    ) {
                        Task { await state.sendKey(device: device, key: key) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.lg)
        }
    }
}

// MARK: - Inspector Building Blocks

/// A titled frosted group, matching the Settings page's section rhythm.
private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text(title.uppercased())
                .font(.ehSectionLabel)
                .foregroundStyle(.secondary)
                .kerning(0.5)

            GlassGroup(cornerRadius: Theme.Radius.md) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A large tile with a headline value and a horizontal capacity bar.
private struct MeterTile: View {
    let icon: String
    let label: String
    let value: String
    var detail: String?
    var fraction: Double?
    var tint: Color = Theme.Palette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.ehSectionLabel)
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let fraction {
                CapacityBar(fraction: fraction, tint: tint)
            }

            Text(detail ?? " ")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassCard(cornerRadius: Theme.Radius.md, tint: tint))
    }
}

private struct CapacityBar: View {
    let fraction: Double
    var tint: Color = Theme.Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Accent.gradient(tint))
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
        .animation(Theme.Motion.smooth, value: fraction)
    }
}

/// One label/value line in the About group, optionally copyable on hover.
private struct DetailRow: View {
    @EnvironmentObject var state: AppState
    let icon: String
    let label: String
    let value: String?
    var copyable: Bool = false
    var last: Bool = false

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.lg) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(label)
                    .font(.ehCaption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: Theme.Space.lg)

                Text(value ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(value == nil ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if copyable, let value, hovered {
                    IconButton(systemImage: "doc.on.doc", help: "Copy", size: 20, symbolSize: 9) {
                        state.copyToClipboard(value, feedback: "\(label) copied")
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(Theme.Motion.fade, value: hovered)

            if !last { Hairline(inset: Theme.Space.lg) }
        }
    }
}

private struct FieldLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.ehCaption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A small labelled chip used for the rotation choices.
private struct ChipButton: View {
    let systemImage: String
    let label: String
    var tint: Color = Theme.Palette.accent
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(hovered ? tint : Color.secondary)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(hovered ? 0.14 : 0)))
                    .overlay(Capsule().strokeBorder(
                        tint.opacity(hovered ? 0.35 : 0.12), lineWidth: 0.75))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.snappy, value: hovered)
    }
}

private struct SendButton: View {
    var tint: Color = Theme.Palette.accent
    var disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(disabled ? AnyShapeStyle(Color.secondary.opacity(0.4))
                                          : AnyShapeStyle(Accent.gradient(tint)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .tooltip("Send to device")
    }
}

// MARK: - Helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
