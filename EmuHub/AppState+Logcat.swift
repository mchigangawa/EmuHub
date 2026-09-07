//
//  AppState+Logcat.swift
//  EmuHub
//
//  AppState methods split out by responsibility.
//

import Foundation
import SwiftUI
import AppKit

extension AppState {
    // MARK: - Logcat

    /// Opens the logcat panel for a device and starts streaming its logs.
    func openLogcat(device: RunningDevice) {
        logcatDevice = device
        logEntries = []
        logcatError = nil
        isLogcatPaused = false
        clearLogcatPackageFilter()
        Task { await loadLogcatPackages(for: device) }

        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            try logcatService.start(
                adbPath: toolchain.adbPath,
                serial: device.serial,
                onEntries: { [weak self] entries in
                    Task { @MainActor in self?.ingestLogEntries(entries) }
                },
                onTerminate: { [weak self] in
                    Task { @MainActor in self?.handleLogcatTermination() }
                }
            )
        } catch {
            logcatError = error.localizedDescription
        }
    }

    /// Closes the panel and stops the stream. Detaches the termination handler
    /// first so closing never looks like an unexpected disconnect.
    func closeLogcat() {
        logcatService.stop()
        clearLogcatPackageFilter()
        logcatPackages = []
        logcatDevice = nil
        logEntries = []
        logcatError = nil
        isLogcatPaused = false
    }

    /// Pause freezes the view by dropping incoming lines; resume picks up live again.
    func toggleLogcatPause() {
        isLogcatPaused.toggle()
    }

    /// Clears the on-screen buffer (does not touch the device-side log buffer).
    func clearLogcat() {
        logEntries = []
    }

    private func ingestLogEntries(_ entries: [LogEntry]) {
        guard logcatDevice != nil, !isLogcatPaused else { return }
        logEntries.append(contentsOf: entries)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    private func handleLogcatTermination() {
        // Only surfaces when the stream ends while the panel is still open
        // (a user-initiated close detaches the handler first).
        guard logcatDevice != nil, logcatError == nil else { return }
        logcatError = "Log stream ended — the device may have disconnected."
    }

// MARK: - "Only this app" Filter

    /// Loads the app list offered in the filter menu. Kept separate from the App
    /// Manager's `packages` so the two panels can't clobber each other's list.
    func loadLogcatPackages(for device: RunningDevice) async {
        isLoadingLogcatPackages = true
        defer { isLoadingLogcatPackages = false }
        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            let apps = try await adbService.listThirdPartyPackages(
                adbPath: toolchain.adbPath, serial: device.serial
            )
            // The panel may have been closed, or moved to another device, while
            // this was in flight.
            guard logcatDevice?.serial == device.serial else { return }
            logcatPackages = apps
        } catch {
            guard logcatDevice?.serial == device.serial else { return }
            logcatPackages = []
        }
    }

    /// Restricts the visible log to one app, or clears the restriction when
    /// passed nil.
    func setLogcatPackageFilter(_ package: String?) {
        guard package != logcatPackageFilter else { return }
        clearLogcatPackageFilter()
        guard let package, let device = logcatDevice else { return }

        logcatPackageFilter = package
        startLogcatPIDPolling(package: package, device: device)
    }

    func clearLogcatPackageFilter() {
        logcatPIDTask?.cancel()
        logcatPIDTask = nil
        logcatPackageFilter = nil
        logcatFilterPIDs = []
    }

    /// An app's PID changes every time it is killed and relaunched, and a crash
    /// loop can churn it repeatedly — so the filter re-resolves on a timer rather
    /// than binding to whatever PID happened to be live when it was switched on.
    /// It also means selecting an app that isn't running yet starts working by
    /// itself once the app launches.
    private func startLogcatPIDPolling(package: String, device: RunningDevice) {
        logcatPIDTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshLogcatPIDs(package: package, device: device)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func refreshLogcatPIDs(package: String, device: RunningDevice) async {
        guard let toolchain = try? AndroidToolchain(sdkPath: sdkPath) else { return }
        let pids = (try? await adbService.processIDs(
            adbPath: toolchain.adbPath, serial: device.serial, package: package
        )) ?? []

        // Ignore a late result if the filter or device changed while it was in flight.
        guard logcatPackageFilter == package, logcatDevice?.serial == device.serial else { return }
        if pids != logcatFilterPIDs { logcatFilterPIDs = pids }
    }

    /// Writes the given log text to the Desktop and reveals it in Finder.
    func saveLog(_ text: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("EmuHub_Logcat_\(timestamp).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            setActionFeedback("Logs saved to Desktop")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastError = "Could not save logs: \(error.localizedDescription)"
        }
    }

    /// Copies the given log text to the clipboard.
    func copyLog(_ text: String) {
        copyToClipboard(text, feedback: "Logs copied to clipboard")
    }

}
