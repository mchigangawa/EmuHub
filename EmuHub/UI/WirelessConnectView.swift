//
//  WirelessConnectView.swift
//  EmuHub
//
//  Attach a physical device over Wi-Fi: pair a new one with the six-digit code
//  (Android 11+), or reconnect one this Mac has already paired with.
//

import SwiftUI

struct WirelessConnectView: View {
    @EnvironmentObject var state: AppState

    @State private var mode: Mode = .pair
    @State private var pairAddress = ""
    @State private var pairCode = ""
    @State private var connectAddress = ""

    enum Mode: String, CaseIterable, Identifiable {
        case pair, connect
        var id: String { rawValue }

        var title: String {
            switch self {
            case .pair:    "Pair New"
            case .connect: "Connect"
            }
        }
    }

    private var accent: Color { Theme.Palette.physical }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                icon: "wifi",
                tint: accent,
                title: "Wireless Debugging",
                subtitle: "Attach a device without a cable",
                onClose: { state.closeWirelessSheet() }
            )

            Hairline(inset: 0).opacity(0.5)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Space.xl) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch mode {
                    case .pair:    pairForm
                    case .connect: connectForm
                    }

                    if let error = state.wirelessError {
                        NoticeBanner(role: .failure, message: error)
                    } else if let success = state.wirelessSuccess {
                        NoticeBanner(role: .success, message: success)
                    }

                    Spacer(minLength: 0)
                }
                .padding(Theme.Space.gutter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground(tint: accent) }
        .animation(Theme.Motion.smooth, value: mode)
        .animation(Theme.Motion.fade, value: state.wirelessError)
        .animation(Theme.Motion.fade, value: state.wirelessSuccess)
    }

    // MARK: - Pair

    private var pairForm: some View {
        VStack(spacing: Theme.Space.xl) {
            StepsCard(steps: [
                "On the device, open Settings → Developer options → Wireless debugging.",
                "Tap “Pair device with pairing code”.",
                "Copy the pairing address, code, and the IP address & port from the main Wireless debugging screen."
            ])

            FormGroup(title: "Pairing") {
                FormField(
                    icon: "point.3.connected.trianglepath.dotted",
                    label: "Pairing address",
                    placeholder: "192.168.1.42:37419",
                    text: $pairAddress,
                    monospaced: true
                )

                Hairline(inset: Theme.Space.lg)

                FormField(
                    icon: "number",
                    label: "Pairing code",
                    placeholder: "123456",
                    text: $pairCode,
                    monospaced: true
                )

                Hairline(inset: Theme.Space.lg)

                FormField(
                    icon: "network",
                    label: "Connect address",
                    placeholder: "192.168.1.42:5555",
                    text: $connectAddress,
                    monospaced: true,
                    footnote: "Shown as “IP address & Port” on the Wireless debugging screen — a different port from the pairing one.",
                    onSubmit: submitPair
                )
            }

            SubmitButton(
                title: "Pair & Connect",
                systemImage: "wifi",
                tint: accent,
                isBusy: state.isWirelessBusy,
                disabled: pairAddress.trimmed.isEmpty || pairCode.trimmed.isEmpty,
                action: submitPair
            )
        }
    }

    private func submitPair() {
        Task {
            await state.pairAndConnect(
                pairAddress: pairAddress,
                code: pairCode,
                connectAddress: connectAddress
            )
            if state.wirelessError == nil { pairCode = "" }
        }
    }

    // MARK: - Connect

    private var connectForm: some View {
        VStack(spacing: Theme.Space.xl) {
            StepsCard(steps: [
                "Use this for a device this Mac has already paired with.",
                "Make sure Wireless debugging is on and the device is on the same network.",
                "Already plugged in over USB? Use “Switch to Wi-Fi” from the device's ••• menu instead — no pairing needed."
            ])

            FormGroup(title: "Connection") {
                FormField(
                    icon: "network",
                    label: "Address",
                    placeholder: "192.168.1.42:5555",
                    text: $connectAddress,
                    monospaced: true,
                    footnote: "Port defaults to 5555 if you leave it off.",
                    onSubmit: submitConnect
                )
            }

            SubmitButton(
                title: "Connect",
                systemImage: "antenna.radiowaves.left.and.right",
                tint: accent,
                isBusy: state.isWirelessBusy,
                disabled: connectAddress.trimmed.isEmpty,
                action: submitConnect
            )
        }
    }

    private func submitConnect() {
        Task { await state.connectWireless(address: connectAddress) }
    }
}

// MARK: - Form Building Blocks

private struct FormGroup<Content: View>: View {
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

private struct FormField: View {
    let icon: String
    let label: String
    let placeholder: String
    @Binding var text: String
    var monospaced: Bool = false
    var footnote: String? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(monospaced ? .ehMonoSmall : .system(size: 12))
                .glassField()
                .onSubmit { onSubmit?() }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.lg)
    }
}

/// Numbered instructions — the device-side half of pairing is easy to get wrong,
/// and the two ports in particular trip people up.
private struct StepsCard: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.physical)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.Palette.physical.opacity(0.14)))

                    Text(step)
                        .font(.ehCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassCard(cornerRadius: Theme.Radius.md))
    }
}

private struct SubmitButton: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.Palette.accent
    var isBusy: Bool
    var disabled: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                if isBusy {
                    ProgressView().controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isBusy ? "Working…" : title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Accent.gradient(tint))
                    .shadow(color: hovered ? tint.opacity(0.4) : .clear, radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled || isBusy)
        .opacity(disabled || isBusy ? 0.55 : 1)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.snappy, value: hovered)
    }
}
