//
//  AdbService+Inspect.swift
//  EmuHub
//
//  Device inspection and one-shot developer actions (rotate, dark mode, deep
//  links, key events, file push).
//

import Foundation

extension AdbService {

    // MARK: - Device Inspection

    /// Sentinels used to slice one combined shell invocation back into sections.
    /// Gathering everything in a single round trip keeps the inspector responsive
    /// — issuing eight separate `adb shell` calls costs roughly eight times as long,
    /// since each one pays full process-spawn and USB round-trip overhead.
    private enum Marker {
        static let props = "__EH_PROPS__"
        static let battery = "__EH_BATTERY__"
        static let display = "__EH_DISPLAY__"
        static let storage = "__EH_STORAGE__"
        static let network = "__EH_NET__"
        static let uptime = "__EH_UPTIME__"

        static let all = [props, battery, display, storage, network, uptime]
    }

    /// Collects everything the Device Inspector shows in one `adb shell` call.
    ///
    /// Every sub-command is best-effort: a device that denies `dumpsys` or has no
    /// `/data` mount still yields whatever other sections succeeded, so the
    /// inspector degrades field by field rather than failing outright.
    func inspect(adbPath: String, serial: String) async throws -> DeviceInfo {
        let script = """
        echo \(Marker.props); \
        getprop ro.product.manufacturer; \
        getprop ro.product.model; \
        getprop ro.build.version.release; \
        getprop ro.build.version.sdk; \
        getprop ro.product.cpu.abi; \
        echo \(Marker.battery); dumpsys battery 2>/dev/null; \
        echo \(Marker.display); wm size 2>/dev/null; wm density 2>/dev/null; \
        echo \(Marker.storage); df /data 2>/dev/null; \
        echo \(Marker.network); ip route 2>/dev/null; \
        echo \(Marker.uptime); cat /proc/uptime 2>/dev/null
        """

        let res = try await Shell.run(adbPath, ["-s", serial, "shell", script])
        return Self.parseInspection(res.stdout)
    }

    /// Splits the combined output on its sentinels and parses each section.
    /// Exposed for testing.
    static func parseInspection(_ output: String) -> DeviceInfo {
        var sections: [String: [String]] = [:]
        var current: String?

        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if Marker.all.contains(line) {
                current = line
                sections[line] = []
            } else if let key = current, !line.isEmpty {
                sections[key, default: []].append(line)
            }
        }

        var info = DeviceInfo()

        // Properties arrive in the fixed order they were requested. A property
        // with no value prints an empty line, which the loop above drops — so
        // index-based assignment would shift. Guard on the expected count.
        let props = sections[Marker.props] ?? []
        if props.count >= 5 {
            info.manufacturer = props[0].nilIfPlaceholder
            info.model = props[1].nilIfPlaceholder
            info.androidVersion = props[2].nilIfPlaceholder
            info.sdkInt = props[3].nilIfPlaceholder
            info.abi = props[4].nilIfPlaceholder
        }

        for line in sections[Marker.battery] ?? [] {
            guard let (key, value) = line.splitKeyValue(separator: ":") else { continue }
            switch key {
            case "level":       info.batteryLevel = Int(value)
            case "status":      info.batteryStatus = Int(value).flatMap(DeviceInfo.BatteryStatus.init(rawValue:))
            // dumpsys reports temperature in tenths of a degree Celsius.
            case "temperature": info.batteryTemperature = Int(value).map { Double($0) / 10 }
            default: break
            }
        }

        for line in sections[Marker.display] ?? [] {
            if let range = line.range(of: "size:") {
                let dims = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let parts = dims.split(separator: "x")
                if parts.count == 2,
                   let w = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let h = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    // "Override size" wins when present because it appears after
                    // "Physical size" and is what the device actually renders at.
                    info.resolutionWidth = w
                    info.resolutionHeight = h
                }
            } else if let range = line.range(of: "density:") {
                info.density = Int(line[range.upperBound...].trimmingCharacters(in: .whitespaces))
            }
        }

        // `df /data` prints a header row then the mount. Columns are
        // Filesystem, 1K-blocks, Used, Available, Use%, Mounted-on.
        if let dataRow = (sections[Marker.storage] ?? []).first(where: { $0.hasSuffix("/data") }) {
            let columns = dataRow.split(separator: " ", omittingEmptySubsequences: true)
            if columns.count >= 3,
               let totalKB = Int64(columns[1]),
               let usedKB = Int64(columns[2]) {
                info.storageTotalBytes = totalKB * 1024
                info.storageUsedBytes = usedKB * 1024
            }
        }

        // `ip route` lines end with "... src <address>" for each interface.
        // Prefer a wlan route so a device with an active VPN or usb tether still
        // reports the address that `adb connect` can actually reach.
        let routes = sections[Marker.network] ?? []
        let preferred = routes.first { $0.contains(" wlan") } ?? routes.first { $0.contains(" src ") }
        if let route = preferred, let range = route.range(of: " src ") {
            info.ipAddress = route[range.upperBound...]
                .split(separator: " ")
                .first
                .map(String.init)
        }

        if let uptimeLine = (sections[Marker.uptime] ?? []).first,
           let first = uptimeLine.split(separator: " ").first {
            info.uptimeSeconds = Double(first)
        }

        return info
    }

    // MARK: - Quick Actions

    /// Screen rotation, expressed as the `user_rotation` values Android accepts.
    enum Rotation: Int, CaseIterable, Sendable {
        case portrait = 0, landscape = 1, portraitUpsideDown = 2, landscapeReversed = 3

        var label: String {
            switch self {
            case .portrait:           "Portrait"
            case .landscape:          "Landscape"
            case .portraitUpsideDown: "Portrait (flipped)"
            case .landscapeReversed:  "Landscape (flipped)"
            }
        }

        var systemImage: String {
            switch self {
            case .portrait, .portraitUpsideDown: "rectangle.portrait.rotate"
            case .landscape, .landscapeReversed: "rectangle.landscape.rotate"
            }
        }
    }

    /// Forces the device into a fixed rotation. Auto-rotate has to be disabled
    /// first, otherwise the accelerometer immediately overrides `user_rotation`.
    func setRotation(adbPath: String, serial: String, rotation: Rotation) async throws {
        _ = try await Shell.run(adbPath, [
            "-s", serial, "shell",
            "settings put system accelerometer_rotation 0; " +
            "settings put system user_rotation \(rotation.rawValue)"
        ])
    }

    /// Re-enables sensor-driven rotation.
    func enableAutoRotate(adbPath: String, serial: String) async throws {
        _ = try await Shell.run(adbPath, [
            "-s", serial, "shell", "settings put system accelerometer_rotation 1"
        ])
    }

    /// Reads the current UI night mode. `cmd uimode night` prints e.g.
    /// "Night mode: yes".
    func isDarkModeEnabled(adbPath: String, serial: String) async throws -> Bool {
        let res = try await Shell.run(adbPath, ["-s", serial, "shell", "cmd uimode night"])
        return res.stdout.lowercased().contains("yes")
    }

    func setDarkMode(adbPath: String, serial: String, enabled: Bool) async throws {
        _ = try await Shell.run(adbPath, [
            "-s", serial, "shell", "cmd uimode night \(enabled ? "yes" : "no")"
        ])
    }

    /// Opens a URL or custom-scheme deep link on the device.
    func openURL(adbPath: String, serial: String, url: String) async throws {
        _ = try await Shell.run(adbPath, [
            "-s", serial, "shell", "am", "start",
            "-a", "android.intent.action.VIEW",
            "-d", url
        ])
    }

    /// Types text into the focused field. `input text` treats spaces as argument
    /// separators, so they must be sent as the literal escape `%s`.
    func inputText(adbPath: String, serial: String, text: String) async throws {
        let encoded = text.replacingOccurrences(of: " ", with: "%s")
        _ = try await Shell.run(adbPath, ["-s", serial, "shell", "input", "text", encoded])
    }

    /// Hardware/navigation keys that are useful to drive from the Mac.
    enum KeyEvent: Int, CaseIterable, Sendable {
        case home = 3, back = 4, recents = 187, power = 26, wake = 224, volumeUp = 24, volumeDown = 25

        var label: String {
            switch self {
            case .home:       "Home"
            case .back:       "Back"
            case .recents:    "Recents"
            case .power:      "Power"
            case .wake:       "Wake"
            case .volumeUp:   "Volume Up"
            case .volumeDown: "Volume Down"
            }
        }

        var systemImage: String {
            switch self {
            case .home:       "house"
            case .back:       "chevron.backward"
            case .recents:    "square.on.square"
            case .power:      "power"
            case .wake:       "sun.max"
            case .volumeUp:   "speaker.wave.2"
            case .volumeDown: "speaker.wave.1"
            }
        }
    }

    func sendKeyEvent(adbPath: String, serial: String, key: KeyEvent) async throws {
        _ = try await Shell.run(adbPath, ["-s", serial, "shell", "input", "keyevent", "\(key.rawValue)"])
    }

    // MARK: - File Transfer

    /// Directory non-APK dropped files are pushed to. `Download` is the one
    /// location reliably visible to the device's Files app across OEM builds.
    static let pushDestination = "/sdcard/Download"

    /// Pushes a file to the device's Download folder, returning the on-device path.
    @discardableResult
    func pushFile(adbPath: String, serial: String, fileURL: URL) async throws -> String {
        let destination = "\(Self.pushDestination)/\(fileURL.lastPathComponent)"
        _ = try await Shell.run(adbPath, ["-s", serial, "push", fileURL.path, destination])
        return destination
    }
}

// MARK: - Parsing Helpers

private extension String {
    /// adb's `getprop` prints nothing for an unset property; `dumpsys` sometimes
    /// prints "unknown". Both should read as "no value" rather than as data.
    var nilIfPlaceholder: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return nil }
        return trimmed
    }

    /// Splits a `key: value` line, trimming both halves. Returns nil when the
    /// line has no separator.
    func splitKeyValue(separator: Character) -> (key: String, value: String)? {
        guard let index = firstIndex(of: separator) else { return nil }
        let key = self[..<index].trimmingCharacters(in: .whitespaces)
        let value = self[self.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }
}

// MARK: - App Settings

extension AdbService {
    /// Opens the system App Info screen for a package on the device — the
    /// fastest route to permissions, storage, and notification settings.
    func openAppSettings(adbPath: String, serial: String, package: String) async throws {
        _ = try await Shell.run(adbPath, [
            "-s", serial, "shell", "am", "start",
            "-a", "android.settings.APPLICATION_DETAILS_SETTINGS",
            "-d", "package:\(package)"
        ])
    }
}
