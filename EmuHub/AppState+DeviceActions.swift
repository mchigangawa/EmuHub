//
//  AppState+DeviceActions.swift
//  EmuHub
//
//  AppState methods split out by responsibility.
//

import Foundation
import SwiftUI
import AppKit

extension AppState {
    // MARK: - Screenshot

    /// Captures a screenshot from the device and saves it to the Desktop.
    /// Opens the file in the default image viewer on success.
    func captureScreenshot(device: RunningDevice) async {
        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            let url = try await adbService.captureScreenshot(
                adbPath: toolchain.adbPath,
                serial: device.serial
            )
            setActionFeedback("Screenshot saved to Desktop")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastError = "Screenshot failed: \(error.localizedDescription)"
        }
    }

    // MARK: - APK Install

    /// Installs an APK file onto a running device or emulator.
    func installAPK(device: RunningDevice, url: URL) async {
        installingAPK.insert(device.serial)
        lastError = nil
        defer { installingAPK.remove(device.serial) }

        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            try await adbService.installAPK(
                adbPath: toolchain.adbPath,
                serial: device.serial,
                apkURL: url
            )
            setActionFeedback("APK installed on \(device.displayName)")
        } catch {
            lastError = "Install failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Reboot

    func reboot(device: RunningDevice, target: AdbService.RebootTarget) async {
        busyDevices.insert(device.serial)
        defer { busyDevices.remove(device.serial) }
        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            try await adbService.reboot(adbPath: toolchain.adbPath, serial: device.serial, target: target)
            setActionFeedback("\(device.displayName): \(target.label.lowercased())…")
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshAll()
        } catch {
            lastError = "Reboot failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Open adb shell in Terminal

    /// Opens Terminal.app with an interactive `adb shell` session for the device.
    func openShell(device: RunningDevice) async {
        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            // Quote both path and serial: SDK paths and wireless TLS serials can contain spaces.
            let shellCmd = "\"\(toolchain.adbPath)\" -s \"\(device.serial)\" shell"
            let escaped = shellCmd
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            _ = try await Shell.run("/usr/bin/osascript", [
                "-e", "tell application \"Terminal\" to do script \"\(escaped)\"",
                "-e", "tell application \"Terminal\" to activate"
            ])
        } catch {
            lastError = "Could not open Terminal: \(error.localizedDescription)"
        }
    }

    // MARK: - Clipboard

    func copySerial(device: RunningDevice) {
        copyToClipboard(device.serial, feedback: "Serial copied to clipboard")
    }

    /// Copies the connection address. For Wi-Fi devices this is the `host:port`
    /// or TLS serial; otherwise falls back to the raw serial.
    func copyAddress(device: RunningDevice) {
        copyToClipboard(device.serial, feedback: "Address copied to clipboard")
    }

    func copyToClipboard(_ string: String, feedback: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        setActionFeedback(feedback)
    }

    // MARK: - App Management

    func openAppManager(device: RunningDevice) {
        appManagerDevice = device
        packages = []
        packagesError = nil
        Task { await loadPackages(for: device) }
    }

    func closeAppManager() {
        appManagerDevice = nil
        packages = []
        packagesError = nil
        busyPackage = nil
    }

    func loadPackages(for device: RunningDevice) async {
        isLoadingPackages = true
        packagesError = nil
        defer { isLoadingPackages = false }
        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            packages = try await adbService.listThirdPartyPackages(
                adbPath: toolchain.adbPath, serial: device.serial
            )
        } catch {
            packagesError = error.localizedDescription
            packages = []
        }
    }

    func launchApp(device: RunningDevice, package: String) async {
        await runPackageAction(device: device, package: package, feedback: "Launched \(package)") {
            try await self.adbService.launchApp(adbPath: $0, serial: device.serial, package: package)
        }
    }

    func forceStopApp(device: RunningDevice, package: String) async {
        await runPackageAction(device: device, package: package, feedback: "Force-stopped \(package)") {
            try await self.adbService.forceStop(adbPath: $0, serial: device.serial, package: package)
        }
    }

    func clearAppData(device: RunningDevice, package: String) async {
        await runPackageAction(device: device, package: package, feedback: "Cleared data for \(package)") {
            try await self.adbService.clearAppData(adbPath: $0, serial: device.serial, package: package)
        }
    }

    func openAppSettings(device: RunningDevice, package: String) async {
        await runPackageAction(device: device, package: package, feedback: "Opened App Info for \(package)") {
            try await self.adbService.openAppSettings(adbPath: $0, serial: device.serial, package: package)
        }
    }

    func uninstallApp(device: RunningDevice, package: String) async {
        await runPackageAction(device: device, package: package, feedback: "Uninstalled \(package)") {
            try await self.adbService.uninstall(adbPath: $0, serial: device.serial, package: package)
        }
        // Drop the package from the list on success (only if no error surfaced).
        if packagesError == nil { packages.removeAll { $0 == package } }
    }

    private func runPackageAction(
        device: RunningDevice,
        package: String,
        feedback: String,
        _ action: @escaping (_ adbPath: String) async throws -> Void
    ) async {
        busyPackage = package
        defer { busyPackage = nil }
        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            try await action(toolchain.adbPath)
            setActionFeedback(feedback)
        } catch {
            lastError = "Action failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Screen Recording

    func toggleScreenRecording(device: RunningDevice) async {
        if recordingSerials.contains(device.serial) {
            await stopScreenRecording(device: device)
        } else {
            await startScreenRecording(device: device)
        }
    }

    private func startScreenRecording(device: RunningDevice) async {
        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            let timestamp = Int(Date().timeIntervalSince1970)
            let devicePath = adbService.screenRecordDevicePath(timestamp: timestamp)

            // Cap the capture resolution: tall/high-density displays fail screenrecord's
            // encoder at native size and produce an empty (0-second) file.
            let dims = try? await adbService.displaySize(adbPath: toolchain.adbPath, serial: device.serial)
            let recordSize = dims.flatMap { $0 }.map {
                AdbService.cappedRecordingSize(width: $0.width, height: $0.height)
            }

            let process = try adbService.startScreenRecording(
                adbPath: toolchain.adbPath, serial: device.serial,
                devicePath: devicePath, size: recordSize
            )
            screenRecordings[device.serial] = (process, devicePath)
            recordingSerials.insert(device.serial)
            setActionFeedback("Recording \(device.displayName)… (max 3 min)")
        } catch {
            lastError = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func stopScreenRecording(device: RunningDevice) async {
        guard let recording = screenRecordings[device.serial] else {
            recordingSerials.remove(device.serial)
            return
        }
        screenRecordings[device.serial] = nil
        recordingSerials.remove(device.serial)
        busyDevices.insert(device.serial)
        defer { busyDevices.remove(device.serial) }
        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            let url = try await adbService.stopScreenRecording(
                adbPath: toolchain.adbPath,
                serial: device.serial,
                devicePath: recording.devicePath,
                localProcess: recording.process
            )
            setActionFeedback("Recording saved to Desktop")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastError = "Recording failed: \(error.localizedDescription)"
        }
    }

}
