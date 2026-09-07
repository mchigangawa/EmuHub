//
//  DeviceInfo.swift
//  EmuHub
//
//  A snapshot of everything the Device Inspector shows for one device, gathered
//  in a single adb round trip.
//

import Foundation

struct DeviceInfo: Equatable, Sendable {
    var manufacturer: String?
    var model: String?
    var androidVersion: String?
    var sdkInt: String?
    var abi: String?

    /// Physical resolution in pixels.
    var resolutionWidth: Int?
    var resolutionHeight: Int?
    /// Screen density in dpi.
    var density: Int?

    /// Battery charge 0–100.
    var batteryLevel: Int?
    /// Decoded `BatteryManager.BATTERY_STATUS_*` value.
    var batteryStatus: BatteryStatus?
    /// Battery temperature in degrees Celsius.
    var batteryTemperature: Double?

    /// `/data` partition usage in bytes.
    var storageUsedBytes: Int64?
    var storageTotalBytes: Int64?

    /// Wi-Fi IPv4 address, when the device is on a network.
    var ipAddress: String?
    /// Seconds since boot.
    var uptimeSeconds: Double?

    enum BatteryStatus: Int, Sendable {
        case unknown = 1, charging = 2, discharging = 3, notCharging = 4, full = 5

        var label: String {
            switch self {
            case .unknown:     "Unknown"
            case .charging:    "Charging"
            case .discharging: "On battery"
            case .notCharging: "Not charging"
            case .full:        "Full"
            }
        }

        var systemImage: String {
            switch self {
            case .charging:    "battery.100.bolt"
            case .full:        "battery.100"
            case .discharging: "battery.50"
            default:           "battery.25"
            }
        }
    }

    // MARK: - Formatted Values

    var resolutionText: String? {
        guard let w = resolutionWidth, let h = resolutionHeight else { return nil }
        let densityText = density.map { " · \($0) dpi" } ?? ""
        return "\(w) × \(h)\(densityText)"
    }

    var batteryText: String? {
        guard let level = batteryLevel else { return nil }
        let status = batteryStatus.map { " · \($0.label)" } ?? ""
        return "\(level)%\(status)"
    }

    var temperatureText: String? {
        batteryTemperature.map { String(format: "%.1f °C", $0) }
    }

    var storageText: String? {
        guard let used = storageUsedBytes, let total = storageTotalBytes, total > 0 else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB]
        return "\(f.string(fromByteCount: total - used)) free of \(f.string(fromByteCount: total))"
    }

    /// Fraction of `/data` in use, for the inspector's capacity meter.
    var storageFraction: Double? {
        guard let used = storageUsedBytes, let total = storageTotalBytes, total > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(total)))
    }

    var uptimeText: String? {
        guard let seconds = uptimeSeconds else { return nil }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var osText: String? {
        guard let version = androidVersion else { return sdkInt.map { "API \($0)" } }
        let api = sdkInt.map { " · API \($0)" } ?? ""
        return "Android \(version)\(api)"
    }

    var hardwareText: String? {
        let name = [manufacturer, model].compactMap { $0 }.joined(separator: " ")
        guard !name.isEmpty else { return abi }
        return abi.map { "\(name) · \($0)" } ?? name
    }
}
