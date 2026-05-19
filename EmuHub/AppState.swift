//
//  AppState.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import Foundation
import SwiftUI
import AppKit
import Combine
import ServiceManagement
import Carbon.HIToolbox

@MainActor
final class AppState: ObservableObject {
    @Published var avds: [AVD] = []
    @Published var running: [RunningDevice] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var lastAction: String?          // transient success feedback (auto-clears)
    @Published var installingAPK: Set<String> = [] // serials currently installing an APK
    @Published var lastRefreshAt: Date?
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginError: String?
    @Published var isCheckingForUpdates = false
    @Published var updateCheckResult: UpdateCheckResult?
    @Published var updateError: String?
    @Published var isUpdating = false
    @Published var updateStage: String?
    @Published var isCreatingAVD = false
    @Published var avdCreationError: String?

    @AppStorage("sdkPath") var sdkPath: String = ""
    @AppStorage("emulatorExtraArgs") var emulatorExtraArgs: String = "-no-snapshot-load"
    @AppStorage("autoRefreshSeconds") var autoRefreshSeconds: Double = 10

    let emulatorService = EmulatorService()
    let adbService = AdbService()
    let releaseUpdateService = ReleaseUpdateService()

    /// Persistent in-session cache of physical device properties keyed by serial.
    private var deviceInfoCache: [String: (model: String?, version: String?)] = [:]

    private var refreshTask: Task<Void, Never>?
    private var actionFeedbackTask: Task<Void, Never>?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?

    init() {
        refreshLaunchAtLoginState()
        registerHotKey()
    }

    // MARK: - Global Hot Key (⌥⌘X)

    /// Registers a process-global ⌥⌘X hotkey via Carbon that toggles the menu bar popover.
    /// Carbon hotkeys work regardless of which app is frontmost and require no Accessibility
    /// permission, unlike `NSEvent.addGlobalMonitorForEvents`.
    private func registerHotKey() {
        let modifiers: UInt32 = UInt32(optionKey | cmdKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_X)
        let hotKeyID = EventHotKeyID(signature: 0x454D5548 /* 'EMUH' */, id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let state = Unmanaged<AppState>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { state.toggleMenuBarPopover() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &hotKeyEventHandler
        )

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func toggleMenuBarPopover() {
        let windows = NSApp.windows

        // SwiftUI's MenuBarExtra(.window) panel is an NSPanel of class
        // `MenuBarExtraWindow<…>`. It's lazy-instantiated on the first user click,
        // so if it doesn't exist yet we have to bootstrap it via the status item.
        if let panel = windows.first(where: {
            String(describing: type(of: $0)).contains("MenuBarExtraWindow")
        }) {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        // Panel not yet created — click the status item button to make SwiftUI build it.
        for window in windows where String(describing: type(of: window)) == "NSStatusBarWindow" {
            if let button = AppState.findStatusBarButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findStatusBarButton(in: subview) { return button }
        }
        return nil
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAll()
                try? await Task.sleep(nanoseconds: UInt64(self.autoRefreshSeconds * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Refresh

    func refreshAll() async {
        ensureSdkPath()
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
        }

        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)

            let avdNames = try await emulatorService.listAVDs(emulatorPath: toolchain.emulatorPath)
            self.avds = avdNames.map { AVD(name: $0) }

            var devices = try await adbService.listRunning(adbPath: toolchain.adbPath)
            await enrichDevices(&devices, adbPath: toolchain.adbPath)
            self.running = devices
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Enriches a device list with model info (physical) and AVD names (emulators).
    /// Concurrent adb queries; caches physical device properties for subsequent refreshes.
    private func enrichDevices(_ devices: inout [RunningDevice], adbPath: String) async {
        // Apply already-cached physical device info immediately
        for i in devices.indices where !devices[i].isEmulator {
            if let cached = deviceInfoCache[devices[i].serial] {
                devices[i].model = cached.model
                devices[i].androidVersion = cached.version
            }
        }

        let emulatorIndices = devices.indices.filter {
            devices[$0].isEmulator && devices[$0].state == "device"
        }
        let physicalIndices = devices.indices.filter {
            !devices[$0].isEmulator &&
            devices[$0].state == "device" &&
            deviceInfoCache[devices[$0].serial] == nil
        }

        guard !emulatorIndices.isEmpty || !physicalIndices.isEmpty else { return }

        let service = adbService

        await withTaskGroup(of: (index: Int, key: String, value: String?).self) { group in
            for i in emulatorIndices {
                let serial = devices[i].serial
                group.addTask {
                    let name = try? await service.getEmulatorAVDName(adbPath: adbPath, serial: serial)
                    return (i, "avdName", name)
                }
            }
            for i in physicalIndices {
                let serial = devices[i].serial
                group.addTask {
                    let model = try? await service.getDeviceProperty(adbPath: adbPath, serial: serial, prop: "ro.product.model")
                    return (i, "model", model)
                }
                group.addTask {
                    let ver = try? await service.getDeviceProperty(adbPath: adbPath, serial: serial, prop: "ro.build.version.release")
                    return (i, "version", ver)
                }
            }

            for await result in group {
                let clean = result.value.flatMap { $0.isEmpty ? nil : $0 }
                switch result.key {
                case "avdName": devices[result.index].avdName = clean
                case "model":   devices[result.index].model   = clean
                case "version": devices[result.index].androidVersion = clean
                default: break
                }
            }
        }

        for i in physicalIndices {
            deviceInfoCache[devices[i].serial] = (
                model: devices[i].model,
                version: devices[i].androidVersion
            )
        }
    }

    // MARK: - Emulator Control

    func start(avd: AVD) async {
        await launchAVD(avd: avd)
    }

    /// Launches the AVD forcing a cold boot (skips saved snapshot).
    func coldBoot(avd: AVD) async {
        await launchAVD(avd: avd, prependArgs: ["-no-snapshot-load"])
    }

    /// Launches the AVD after wiping all user data.
    func wipeAndBoot(avd: AVD) async {
        await launchAVD(avd: avd, prependArgs: ["-wipe-data"])
    }

    private func launchAVD(avd: AVD, prependArgs: [String] = []) async {
        do {
            ensureSdkPath()
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)

            let userArgs = emulatorExtraArgs
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }

            // Deduplicate: prependArgs take precedence over user args
            var seen = Set(prependArgs)
            let filteredUser = userArgs.filter { seen.insert($0).inserted }
            let finalArgs = prependArgs + filteredUser

            try await emulatorService.startAVD(
                emulatorPath: toolchain.emulatorPath,
                avdName: avd.name,
                extraArgs: finalArgs
            )

            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop(device: RunningDevice) async {
        guard device.isEmulator else {
            lastError = device.connectionType == .wifi
                ? "This is a physical device. To remove it, disable Wireless Debugging on the device."
                : "This is a physical device. To remove it, unplug the USB cable or disable USB debugging."
            return
        }

        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            try await adbService.stopEmulator(adbPath: toolchain.adbPath, serial: device.serial)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

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

    // MARK: - Action Feedback

    /// Shows a transient success message that auto-dismisses after 3 seconds.
    func setActionFeedback(_ message: String) {
        lastAction = message
        actionFeedbackTask?.cancel()
        actionFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.lastAction == message else { return }
            self.lastAction = nil
        }
    }

    // MARK: - Launch at Login

    func refreshLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginEnabled = false
            launchAtLoginError = "Launch at Login requires macOS 13 or newer."
            return
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginError = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            launchAtLoginEnabled = false
            launchAtLoginError = "Launch at Login requires macOS 13 or newer."
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "Could not update Launch at Login: \(error.localizedDescription)"
        }
    }

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

    // MARK: - Private Helpers

    private func ensureSdkPath() {
        let fm = FileManager.default
        if sdkPath.isEmpty || !fm.fileExists(atPath: sdkPath) {
            let auto = AndroidToolchain.defaultMacSdkPath()
            if fm.fileExists(atPath: auto) { sdkPath = auto }
        }
    }
}
