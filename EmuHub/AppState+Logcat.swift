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
