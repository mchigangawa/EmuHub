//
//  AppState+Inspector.swift
//  EmuHub
//
//  Device Inspector state plus the one-shot developer actions it exposes:
//  rotation, dark mode, deep links, key events, and file push.
//

import Foundation
import SwiftUI
import AppKit

extension AppState {

    // MARK: - Inspector Lifecycle

    func openInspector(device: RunningDevice) {
        inspectorDevice = device
        deviceInfo = nil
        deviceInfoError = nil
        isDarkModeOn = nil
        Task { await loadDeviceInfo(for: device) }
    }

    func closeInspector() {
        inspectorDevice = nil
        deviceInfo = nil
        deviceInfoError = nil
        isDarkModeOn = nil
    }

    func loadDeviceInfo(for device: RunningDevice) async {
        isLoadingDeviceInfo = true
        deviceInfoError = nil
        defer { isLoadingDeviceInfo = false }

        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            let info = try await adbService.inspect(adbPath: toolchain.adbPath, serial: device.serial)
            // The panel may have been dismissed while the query was in flight.
            guard inspectorDevice?.serial == device.serial else { return }
            deviceInfo = info

            // Night mode is a separate query and is allowed to fail quietly —
            // some OEM builds don't implement `cmd uimode`.
            isDarkModeOn = try? await adbService.isDarkModeEnabled(
                adbPath: toolchain.adbPath, serial: device.serial
            )
        } catch {
            guard inspectorDevice?.serial == device.serial else { return }
            deviceInfoError = error.localizedDescription
        }
    }

    // MARK: - Quick Actions

    func setRotation(device: RunningDevice, rotation: AdbService.Rotation) async {
        await runDeviceAction(device: device, feedback: "Rotated to \(rotation.label.lowercased())") {
            try await self.adbService.setRotation(adbPath: $0, serial: device.serial, rotation: rotation)
        }
    }

    func enableAutoRotate(device: RunningDevice) async {
        await runDeviceAction(device: device, feedback: "Auto-rotate enabled") {
            try await self.adbService.enableAutoRotate(adbPath: $0, serial: device.serial)
        }
    }

    func toggleDarkMode(device: RunningDevice) async {
        let target = !(isDarkModeOn ?? false)
        await runDeviceAction(device: device, feedback: target ? "Dark mode on" : "Light mode on") {
            try await self.adbService.setDarkMode(adbPath: $0, serial: device.serial, enabled: target)
        }
        if lastError == nil { isDarkModeOn = target }
    }

    func openURL(device: RunningDevice, url: String) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await runDeviceAction(device: device, feedback: "Opened \(trimmed)") {
            try await self.adbService.openURL(adbPath: $0, serial: device.serial, url: trimmed)
        }
    }

    func sendText(device: RunningDevice, text: String) async {
        guard !text.isEmpty else { return }
        await runDeviceAction(device: device, feedback: "Text sent to \(device.displayName)") {
            try await self.adbService.inputText(adbPath: $0, serial: device.serial, text: text)
        }
    }

    /// Sends the Mac's current clipboard text to the device's focused field.
    func pasteClipboard(device: RunningDevice) async {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            lastError = "The clipboard has no text to send."
            return
        }
        await sendText(device: device, text: text)
    }

    func sendKey(device: RunningDevice, key: AdbService.KeyEvent) async {
        await runDeviceAction(device: device, feedback: "\(key.label) sent") {
            try await self.adbService.sendKeyEvent(adbPath: $0, serial: device.serial, key: key)
        }
    }

    // MARK: - File Push

    /// Pushes a non-APK file dropped on a device card to the device's Downloads.
    func pushFile(device: RunningDevice, url: URL) async {
        installingAPK.insert(device.serial)
        defer { installingAPK.remove(device.serial) }
        await runDeviceAction(
            device: device,
            feedback: "\(url.lastPathComponent) → Download",
            showsBusy: false
        ) {
            try await self.adbService.pushFile(adbPath: $0, serial: device.serial, fileURL: url)
        }
    }

    /// Routes a dropped file to the right transfer: APKs install, anything else
    /// is pushed to the device's Download folder.
    func handleDroppedFile(device: RunningDevice, url: URL) async {
        if url.pathExtension.lowercased() == "apk" {
            await installAPK(device: device, url: url)
        } else {
            await pushFile(device: device, url: url)
        }
    }

    // MARK: - Shared Runner

    /// Runs a device action with consistent busy-state, success feedback, and
    /// error reporting, so each action above stays a single line.
    func runDeviceAction(
        device: RunningDevice,
        feedback: String,
        showsBusy: Bool = true,
        _ action: @escaping (_ adbPath: String) async throws -> Void
    ) async {
        if showsBusy { busyDevices.insert(device.serial) }
        defer { if showsBusy { busyDevices.remove(device.serial) } }

        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            try await action(toolchain.adbPath)
            lastError = nil
            setActionFeedback(feedback)
        } catch {
            lastError = "Action failed: \(error.localizedDescription)"
        }
    }
}
