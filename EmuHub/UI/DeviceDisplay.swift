//
//  DeviceDisplay.swift
//  EmuHub
//

import SwiftUI

// MARK: - Model Extensions

extension RunningDevice {
    var displayName: String {
        if isEmulator {
            if let raw = avdName, !raw.isEmpty {
                var n = raw
                if let r = n.range(of: #"_API_\d+"#, options: .regularExpression) {
                    n = String(n[..<r.lowerBound])
                }
                return n.replacingOccurrences(of: "_", with: " ")
            }
            if let portStr = serial.split(separator: "-").last,
               let port = Int(portStr) {
                let index = (port - 5554) / 2 + 1
                return index > 1 ? "Emulator #\(index)" : "Android Emulator"
            }
            return "Android Emulator"
        }
        return model ?? serial
    }

    var statusDescription: String {
        if isEmulator {
            let portSuffix: String = {
                guard let p = serial.split(separator: "-").last else { return "" }
                return " · port \(p)"
            }()
            switch state {
            case "device":       return "Emulator running\(portSuffix)"
            case "offline":      return "Offline\(portSuffix)"
            case "unauthorized": return "Unauthorized\(portSuffix)"
            default:             return state.capitalized
            }
        }
        if isUnauthorized { return "Tap 'Allow' on your device to authorize USB debugging" }
        if isOffline {
            return connectionType == .wifi
                ? "Device offline — check Wi-Fi connection"
                : "Device offline — check USB cable"
        }
        if state == "device" {
            let ver = androidVersion.map { "Android \($0) · " } ?? ""
            let conn = connectionType == .wifi ? "Wi-Fi connected" : "USB connected"
            return "\(ver)\(conn) · read-only"
        }
        return state.capitalized
    }

    var hasIssue: Bool { isUnauthorized || isOffline }
}

// MARK: - AVD Device Type

enum AVDDeviceType {
    case phone, tablet, tv, wear, automotive, foldable

    var systemImage: String {
        switch self {
        case .phone:      "iphone"
        case .tablet:     "ipad"
        case .tv:         "tv"
        case .wear:       "applewatch"
        case .automotive: "car"
        case .foldable:   "iphone"
        }
    }

    var color: Color {
        switch self {
        case .phone:      .blue
        case .tablet:     .indigo
        case .tv:         .purple
        case .wear:       .pink
        case .automotive: .green
        case .foldable:   .orange
        }
    }
}

extension AVD {
    var deviceType: AVDDeviceType {
        let n = name.lowercased()
        if n.contains("_tv") || n.hasPrefix("tv_") || n.contains("android_tv") { return .tv }
        if n.contains("watch") || n.contains("wear") || n.contains("wearos")   { return .wear }
        if n.contains("automotive") || n.contains("_car_")                      { return .automotive }
        if n.contains("fold") || n.contains("flip")                             { return .foldable }
        if n.contains("tablet") || n.contains("pixel_tablet") ||
           n.contains("tab_")  || n.hasSuffix("_tab")                          { return .tablet }
        return .phone
    }

    var friendlyName: String {
        var n = name
        if let r = n.range(of: #"_API_\d+"#, options: .regularExpression) {
            n = String(n[..<r.lowerBound])
        }
        return n.replacingOccurrences(of: "_", with: " ")
    }

    var subtitle: String {
        let typeName: String
        switch deviceType {
        case .phone:      typeName = "Virtual Device"
        case .tablet:     typeName = "Tablet"
        case .tv:         typeName = "Android TV"
        case .wear:       typeName = "Wear OS"
        case .automotive: typeName = "Automotive"
        case .foldable:   typeName = "Foldable"
        }
        if let r = name.range(of: #"API_(\d+)"#, options: .regularExpression) {
            let level = name[r].replacingOccurrences(of: "API_", with: "")
            return "API \(level) · \(typeName)"
        }
        return typeName
    }
}

