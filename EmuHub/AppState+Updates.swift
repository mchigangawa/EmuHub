//
//  AppState+Updates.swift
//  EmuHub
//
//  AppState methods split out by responsibility.
//

import Foundation
import SwiftUI
import AppKit

extension AppState {
    // MARK: - Updates

    // MARK: - Auto Update

    /// Downloads the release zip, extracts it, writes an update script that waits for
    /// this process to exit then swaps the bundle in-place via rsync, and relaunches.
    func applyUpdate(downloadURL: URL) async {
        isUpdating = true
        updateStage = "Downloading…"
        updateError = nil
        defer {
            if isUpdating {           // only runs when we bail early on error
                isUpdating = false
                updateStage = nil
            }
        }

        do {
            // 1. Download the zip to a temp file
            let (tempZip, _) = try await URLSession.shared.download(from: downloadURL)

            // 2. Create extraction directory
            updateStage = "Extracting…"
            let fm = FileManager.default
            let extractDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

            _ = try await Shell.run("/usr/bin/unzip", ["-q", tempZip.path, "-d", extractDir.path])

            // 3. Find the .app inside the extracted content
            guard let newApp = (try fm.contentsOfDirectory(at: extractDir,
                                                            includingPropertiesForKeys: nil))
                .first(where: { $0.pathExtension == "app" })
            else {
                throw NSError(domain: "EmuHub", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "No .app bundle found in the downloaded archive."
                ])
            }

            // 4. Write an update shell script that:
            //    - waits for this process to fully exit
            //    - rsync-replaces the bundle
            //    - cleans up temp files
            //    - relaunches the updated app
            updateStage = "Preparing…"
            let pid = ProcessInfo.processInfo.processIdentifier
            let currentBundle = Bundle.main.bundleURL.path
            let scriptContent = """
            #!/bin/bash
            # Wait for EmuHub (PID \(pid)) to exit
            while kill -0 \(pid) 2>/dev/null; do
                sleep 0.3
            done
            rsync -a --delete "\(newApp.path)/" "\(currentBundle)/"
            rm -rf "\(extractDir.path)"
            open "\(currentBundle)"
            """
            let scriptURL = fm.temporaryDirectory.appendingPathComponent("emuhub_updater_\(pid).sh")
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            // 5. Launch the script detached so it survives after this process exits
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptURL.path]
            launcher.standardOutput = FileHandle.nullDevice
            launcher.standardError  = FileHandle.nullDevice
            try launcher.run()

            // 6. Quit — the script takes it from here
            updateStage = "Installing…"
            try? await Task.sleep(nanoseconds: 400_000_000) // brief pause so user sees the stage
            NSApp.terminate(nil)

        } catch {
            updateError = "Update failed: \(error.localizedDescription)"
        }
    }

    func checkForUpdates() async {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        isCheckingForUpdates = true
        updateError = nil
        defer { isCheckingForUpdates = false }

        do {
            updateCheckResult = try await releaseUpdateService.checkForUpdates(currentVersion: currentVersion)
        } catch {
            updateCheckResult = nil
            updateError = error.localizedDescription
        }
    }

    // MARK: - AVD Creation

    func createAVD(name: String, systemImagePackage: String, deviceId: String) async {
        isCreatingAVD = true
        avdCreationError = nil
        defer { isCreatingAVD = false }

        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            guard let avdmanagerPath = toolchain.avdmanagerPath else {
                throw NSError(
                    domain: "EmuHub", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "avdmanager not found. Install Android Command-line Tools via SDK Manager."]
                )
            }
            try await emulatorService.createAVD(
                avdmanagerPath: avdmanagerPath,
                name: name,
                package: systemImagePackage,
                device: deviceId
            )
            setActionFeedback("AVD \"\(name)\" created successfully")
            await refreshAll()
        } catch {
            avdCreationError = error.localizedDescription
        }
    }

    /// Permanently deletes an AVD via `avdmanager`. Refuses while the AVD is
    /// running so we never delete data out from under a live emulator.
    func deleteAVD(avd: AVD) async {
        if running.contains(where: { $0.isEmulator && $0.avdName == avd.name }) {
            lastError = "Stop \"\(avd.friendlyName)\" before deleting it."
            return
        }

        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            guard let avdmanagerPath = toolchain.avdmanagerPath else {
                throw NSError(
                    domain: "EmuHub", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "avdmanager not found. Install Android Command-line Tools via SDK Manager."]
                )
            }
            try await emulatorService.deleteAVD(avdmanagerPath: avdmanagerPath, name: avd.name)
            setActionFeedback("AVD \"\(avd.friendlyName)\" deleted")
            await refreshAll()
        } catch {
            lastError = "Could not delete AVD: \(error.localizedDescription)"
        }
    }

}
