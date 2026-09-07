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

    // Device actions
    @Published var recordingSerials: Set<String> = []      // serials currently screen-recording
    @Published var busyDevices: Set<String> = []           // serials with a blocking action in flight

    // App management sheet
    @Published var appManagerDevice: RunningDevice?
    @Published var packages: [String] = []
    @Published var isLoadingPackages = false
    @Published var packagesError: String?
    @Published var busyPackage: String?                    // package with an action in flight

    // Logcat viewer
    @Published var logcatDevice: RunningDevice?            // device whose logs are showing
    @Published var logEntries: [LogEntry] = []
    @Published var logcatError: String?
    @Published var isLogcatPaused = false

    // Device inspector
    @Published var inspectorDevice: RunningDevice?         // device whose details are showing
    @Published var deviceInfo: DeviceInfo?
    @Published var isLoadingDeviceInfo = false
    @Published var deviceInfoError: String?
    @Published var isDarkModeOn: Bool?                     // nil until read from the device

    // Wireless debugging
    @Published var isWirelessSheetOpen = false
    @Published var isWirelessBusy = false
    @Published var wirelessError: String?
    @Published var wirelessSuccess: String?

    /// AVDs whose emulator we've launched but that haven't shown up in `adb devices`
    /// yet. Drives the "Starting…" state on the card so a launch doesn't look inert
    /// during the ~10s an emulator takes to register.
    @Published var bootingAVDs: Set<String> = []

    @AppStorage("sdkPath") var sdkPath: String = ""
    @AppStorage("emulatorExtraArgs") var emulatorExtraArgs: String = "-no-snapshot-load"
    @AppStorage("autoRefreshSeconds") var autoRefreshSeconds: Double = 10

    let emulatorService = EmulatorService()
    let adbService = AdbService()
    let releaseUpdateService = ReleaseUpdateService()
    let logcatService = LogcatService()

    /// Cap on retained log lines; oldest are dropped past this to bound memory.
    let maxLogEntries = 5000

    /// Persistent in-session cache of physical device properties keyed by serial.
    private var deviceInfoCache: [String: (model: String?, version: String?)] = [:]

    /// Cache of resolved emulator AVD names keyed by serial, so steady-state polls
    /// don't re-run `adb emu avd name` for emulators we've already identified.
    private var emulatorNameCache: [String: String] = [:]

    /// In-progress screen recordings: serial → (process, device-side mp4 path).
    var screenRecordings: [String: (process: Process, devicePath: String)] = [:]

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

    /// Number of device polls between full AVD-list scans. `emulator -list-avds`
    /// is slow (it spins up the emulator binary) and AVDs change rarely, so we
    /// poll devices on every tick but only rescan AVDs occasionally.
    private let avdRescanEveryNPolls = 6

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            var tick = 0
            while !Task.isCancelled {
                // Background polls are silent (no spinner) and only rescan the AVD
                // list every Nth tick so the slow emulator binary call doesn't run
                // every cycle.
                await self.refreshAll(silent: true, includeAVDs: tick % self.avdRescanEveryNPolls == 0)
                tick &+= 1
                try? await Task.sleep(nanoseconds: UInt64(self.autoRefreshSeconds * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Refresh

    /// Refreshes device (and optionally AVD) state.
    /// - Parameters:
    ///   - silent: when true, doesn't toggle `isRefreshing` (used by the background
    ///     poll so the Refresh spinner doesn't flicker every interval).
    ///   - includeAVDs: when true, rescans the AVD list via the (slow) emulator binary.
    func refreshAll(silent: Bool = false, includeAVDs: Bool = true) async {
        ensureSdkPath()
        if !silent { isRefreshing = true }
        defer {
            if !silent { isRefreshing = false }
            lastRefreshAt = Date()
        }

        do {
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)

            // Run the slow AVD scan and the device list concurrently when both
            // are needed, so the emulator-binary call doesn't block device updates.
            if includeAVDs {
                async let avdNamesTask = emulatorService.listAVDs(emulatorPath: toolchain.emulatorPath)
                async let devicesTask = adbService.listRunning(adbPath: toolchain.adbPath)

                let avdNames = try await avdNamesTask
                var devices = try await devicesTask
                await enrichDevices(&devices, adbPath: toolchain.adbPath)

                applyAVDs(avdNames)
                applyRunning(devices)
            } else {
                var devices = try await adbService.listRunning(adbPath: toolchain.adbPath)
                await enrichDevices(&devices, adbPath: toolchain.adbPath)
                applyRunning(devices)
            }

            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Publishes a new AVD list only when it actually changed, to avoid waking
    /// SwiftUI (and re-rendering every card) on every identical poll.
    private func applyAVDs(_ names: [String]) {
        let next = names.map { AVD(name: $0) }
        if next != avds { avds = next }
    }

    /// Publishes a new device list only when it changed, and retires any
    /// "starting…" placeholder whose emulator has now registered with adb.
    private func applyRunning(_ devices: [RunningDevice]) {
        if devices != running { running = devices }

        if !bootingAVDs.isEmpty {
            let live = Set(devices.compactMap(\.avdName))
            let settled = bootingAVDs.intersection(live)
            if !settled.isEmpty { bootingAVDs.subtract(settled) }
        }
    }

    /// Names of AVDs that already have a running emulator, so the Available list
    /// can mark them instead of offering a second launch that would just fail.
    var runningAVDNames: Set<String> {
        Set(running.compactMap(\.avdName))
    }

    /// Enriches a device list with model info (physical) and AVD names (emulators).
    /// Concurrent adb queries; caches physical device properties for subsequent refreshes.
    private func enrichDevices(_ devices: inout [RunningDevice], adbPath: String) async {
        // Drop cache entries for devices that are no longer connected so a serial
        // reused by a different emulator/device can't surface stale info.
        let currentSerials = Set(devices.map(\.serial))
        deviceInfoCache = deviceInfoCache.filter { currentSerials.contains($0.key) }
        emulatorNameCache = emulatorNameCache.filter { currentSerials.contains($0.key) }

        // Apply already-cached info immediately (emulator names and physical props).
        for i in devices.indices {
            if devices[i].isEmulator {
                if let name = emulatorNameCache[devices[i].serial] {
                    devices[i].avdName = name
                }
            } else if let cached = deviceInfoCache[devices[i].serial] {
                devices[i].model = cached.model
                devices[i].androidVersion = cached.version
            }
        }

        // Only query what we don't already have cached.
        let emulatorIndices = devices.indices.filter {
            devices[$0].isEmulator &&
            devices[$0].state == "device" &&
            emulatorNameCache[devices[$0].serial] == nil
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

        for i in emulatorIndices {
            if let name = devices[i].avdName, !name.isEmpty {
                emulatorNameCache[devices[i].serial] = name
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
        bootingAVDs.insert(avd.name)
        // An emulator that never registers (bad image, crash on boot) would leave
        // the card stuck on "Starting…", so give the placeholder a hard expiry.
        scheduleBootTimeout(for: avd.name)

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
            bootingAVDs.remove(avd.name)
            lastError = error.localizedDescription
        }
    }

    /// Clears a boot placeholder if the emulator hasn't registered within the
    /// window a cold boot realistically needs.
    private func scheduleBootTimeout(for name: String, seconds: UInt64 = 90) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            self?.bootingAVDs.remove(name)
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

    // MARK: - Private Helpers

    func ensureSdkPath() {
        let fm = FileManager.default
        if sdkPath.isEmpty || !fm.fileExists(atPath: sdkPath) {
            let auto = AndroidToolchain.defaultMacSdkPath()
            if fm.fileExists(atPath: auto) { sdkPath = auto }
        }
    }
}
