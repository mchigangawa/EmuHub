//
//  AdbService.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import Foundation

struct AdbService {

    // MARK: - Device Listing

    func listRunning(adbPath: String) async throws -> [RunningDevice] {
        _ = try? await Shell.run(adbPath, ["start-server"])

        // `-l` adds product/model/transport_id metadata; transport_id is used for
        // deduplication of wireless TLS serials that share a normalized base serial.
        let res = try await Shell.run(adbPath, ["devices", "-l"])

        return ADBParser
            .deduplicate(ADBParser.parseOutput(res.stdout))
            .map { RunningDevice(serial: $0.serial, state: $0.state) }
    }

    // MARK: - Emulator Control

    func stopEmulator(adbPath: String, serial: String) async throws {
        _ = try? await Shell.run(adbPath, ["start-server"])
        _ = try await Shell.run(adbPath, ["-s", serial, "emu", "kill"])
    }

    // MARK: - Device Property Queries

    /// Returns the AVD name for a running emulator via `adb emu avd name`.
    /// Output is typically "AVD_Name\nOK" — we return the first non-empty, non-"OK" line.
    func getEmulatorAVDName(adbPath: String, serial: String) async throws -> String? {
        let res = try await Shell.run(adbPath, ["-s", serial, "emu", "avd", "name"])
        return res.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "OK" }
    }

    /// Reads a single system property from a connected device.
    func getDeviceProperty(adbPath: String, serial: String, prop: String) async throws -> String? {
        let res = try await Shell.run(adbPath, ["-s", serial, "shell", "getprop", prop])
        let value = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Screenshot

    /// Captures a screenshot from the device and saves it to the Mac Desktop.
    /// Returns the saved file URL.
    func captureScreenshot(adbPath: String, serial: String) async throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let devicePath = "/sdcard/emuhub_ss_\(timestamp).png"
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("EmuHub_Screenshot_\(timestamp).png")

        // Capture to device storage
        _ = try await Shell.run(adbPath, ["-s", serial, "shell", "screencap", "-p", devicePath])

        // Pull the PNG to Desktop
        _ = try await Shell.run(adbPath, ["-s", serial, "pull", devicePath, desktopURL.path])

        // Clean up from device (best effort)
        _ = try? await Shell.run(adbPath, ["-s", serial, "shell", "rm", devicePath])

        return desktopURL
    }

    // MARK: - APK Installation

    /// Installs an APK onto a connected device or emulator.
    /// Uses `-r` to allow reinstalling over an existing package.
    func installAPK(adbPath: String, serial: String, apkURL: URL) async throws {
        _ = try await Shell.run(adbPath, ["-s", serial, "install", "-r", apkURL.path])
    }

    // MARK: - Reboot

    enum RebootTarget: String, CaseIterable {
        case system, recovery, bootloader

        /// adb argument; system reboot takes no extra argument.
        var argument: String? { self == .system ? nil : rawValue }

        var label: String {
            switch self {
            case .system:     "Reboot"
            case .recovery:   "Reboot to Recovery"
            case .bootloader: "Reboot to Bootloader"
            }
        }

        var systemImage: String {
            switch self {
            case .system:     "arrow.clockwise"
            case .recovery:   "wrench.and.screwdriver"
            case .bootloader: "terminal"
            }
        }
    }

    /// Reboots a connected device or emulator, optionally into recovery/bootloader.
    func reboot(adbPath: String, serial: String, target: RebootTarget) async throws {
        var args = ["-s", serial, "reboot"]
        if let arg = target.argument { args.append(arg) }
        _ = try await Shell.run(adbPath, args)
    }

    // MARK: - App Management

    /// Lists installed third-party (user-installed) packages, sorted alphabetically.
    /// Uses `pm list packages -3` to exclude system apps that aren't useful to act on.
    func listThirdPartyPackages(adbPath: String, serial: String) async throws -> [String] {
        let res = try await Shell.run(adbPath, ["-s", serial, "shell", "pm", "list", "packages", "-3"])
        return res.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { line in
                line.hasPrefix("package:") ? String(line.dropFirst("package:".count)) : nil
            }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Launches an app by its package name via the monkey launcher intent.
    func launchApp(adbPath: String, serial: String, package: String) async throws {
        _ = try await Shell.run(adbPath, [
            "-s", serial, "shell", "monkey",
            "-p", package, "-c", "android.intent.category.LAUNCHER", "1"
        ])
    }

    /// Force-stops a running app.
    func forceStop(adbPath: String, serial: String, package: String) async throws {
        _ = try await Shell.run(adbPath, ["-s", serial, "shell", "am", "force-stop", package])
    }

    /// Clears an app's user data (equivalent to "Clear storage" in Settings).
    func clearAppData(adbPath: String, serial: String, package: String) async throws {
        _ = try await Shell.run(adbPath, ["-s", serial, "shell", "pm", "clear", package])
    }

    /// Uninstalls an app by package name.
    func uninstall(adbPath: String, serial: String, package: String) async throws {
        _ = try await Shell.run(adbPath, ["-s", serial, "uninstall", package])
    }

    // MARK: - Screen Recording

    /// Remote path used for an in-progress screen recording on the device.
    func screenRecordDevicePath(timestamp: Int) -> String {
        "/sdcard/emuhub_rec_\(timestamp).mp4"
    }

    /// Reads the device display resolution via `wm size`. Prefers an override size
    /// when one is set. Returns nil if the output can't be parsed.
    func displaySize(adbPath: String, serial: String) async throws -> (width: Int, height: Int)? {
        let res = try await Shell.run(adbPath, ["-s", serial, "shell", "wm", "size"])

        func parseDimensions(_ s: Substring) -> (Int, Int)? {
            let parts = s.split(separator: "x")
            guard parts.count == 2,
                  let w = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let h = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return (w, h)
        }

        var physical: (Int, Int)?
        var override: (Int, Int)?
        for raw in res.stdout.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let r = line.range(of: "Physical size:") {
                physical = parseDimensions(line[r.upperBound...].trimmingCharacters(in: .whitespaces)[...])
            } else if let r = line.range(of: "Override size:") {
                override = parseDimensions(line[r.upperBound...].trimmingCharacters(in: .whitespaces)[...])
            }
        }
        return override ?? physical
    }

    /// Builds a `screenrecord --size` value that preserves aspect ratio while capping
    /// the longest side. Some emulators/codecs reject very tall native resolutions
    /// (e.g. 1280×2856 fails to configure the AVC encoder), so capping is required for
    /// a valid, playable recording. Dimensions are forced even for H.264.
    static func cappedRecordingSize(width: Int, height: Int, maxDimension: Int = 1280) -> String {
        func even(_ v: Int) -> Int { max(2, v - (v % 2)) }
        let longest = max(width, height)
        guard longest > maxDimension else { return "\(even(width))x\(even(height))" }
        let scale = Double(maxDimension) / Double(longest)
        return "\(even(Int((Double(width) * scale).rounded())))x\(even(Int((Double(height) * scale).rounded())))"
    }

    /// Starts `screenrecord` on the device, writing to `devicePath`.
    /// Returns the detached Process so the caller can stop it later. The process
    /// blocks until screenrecord ends (signalled via `stopScreenRecording`) or
    /// hits adb's 180-second cap. Pass an explicit `size` ("WxH") for reliable
    /// capture on high-resolution devices.
    func startScreenRecording(adbPath: String, serial: String, devicePath: String, size: String?) throws -> Process {
        var args = ["-s", serial, "shell", "screenrecord"]
        if let size { args += ["--size", size] }
        args.append(devicePath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = args
        // Discard output: an unread pipe buffer can fill and stall screenrecord.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// Stops an in-progress recording cleanly, pulls the file to the Desktop, and
    /// removes it from the device.
    ///
    /// `screenrecord` only writes a valid MP4 (moov atom / trailer) when it receives
    /// SIGINT and is allowed to flush. We therefore signal the *device-side* process
    /// and wait for the local `adb shell` to return on its own — killing the local
    /// adb process instead would sever the shell mid-flush and produce an unplayable
    /// (often black/empty) file.
    func stopScreenRecording(
        adbPath: String,
        serial: String,
        devicePath: String,
        localProcess: Process?
    ) async throws -> URL {
        // Ask the device-side recorder to stop and finalize the file.
        _ = try? await Shell.run(adbPath, ["-s", serial, "shell", "pkill", "-INT", "screenrecord"])

        // Wait (up to ~6s) for the streaming `adb shell screenrecord` to exit cleanly,
        // which happens once the device has finished writing the MP4 trailer.
        if let process = localProcess {
            let deadline = Date().addingTimeInterval(6)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            if process.isRunning { process.terminate() }
        } else {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        // Small extra settle so the file is fully closed on the device before pulling.
        try? await Task.sleep(nanoseconds: 400_000_000)

        let timestamp = devicePath
            .components(separatedBy: "_").last?
            .replacingOccurrences(of: ".mp4", with: "") ?? "\(Int(Date().timeIntervalSince1970))"
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("EmuHub_Recording_\(timestamp).mp4")

        _ = try await Shell.run(adbPath, ["-s", serial, "pull", devicePath, desktopURL.path])
        _ = try? await Shell.run(adbPath, ["-s", serial, "shell", "rm", devicePath])

        return desktopURL
    }
}
