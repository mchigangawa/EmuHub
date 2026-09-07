//
//  AdbService+Wireless.swift
//  EmuHub
//
//  Wireless debugging: pairing (Android 11+), connecting, disconnecting, and
//  promoting an already-attached USB device onto the network.
//

import Foundation

enum WirelessError: LocalizedError {
    case pairFailed(String)
    case connectFailed(String)
    case noAddress

    var errorDescription: String? {
        switch self {
        case .pairFailed(let detail):
            return detail.isEmpty ? "Pairing failed. Check the address and code, then try again." : detail
        case .connectFailed(let detail):
            return detail.isEmpty ? "Could not connect to that address." : detail
        case .noAddress:
            return "Couldn't read the device's Wi-Fi address. Make sure it's on the same network as this Mac."
        }
    }
}

extension AdbService {

    /// `adb pair` and `adb connect` report failure in their *stdout* text while
    /// still exiting 0, so the exit code alone can't be trusted — the output has
    /// to be inspected for these markers.
    private static func failureDetail(in output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        let markers = ["failed", "cannot", "unable", "error", "refused", "timeout", "timed out"]
        guard markers.contains(where: lowered.contains) else { return nil }
        // Surface adb's own wording — it's more specific than anything generic.
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }

    // MARK: - Pair (Android 11+)

    /// Pairs with a device using the six-digit code from
    /// Developer options → Wireless debugging → Pair device with pairing code.
    ///
    /// The pairing address and port are *different* from the connection address
    /// and port; the device shows both on that screen.
    func pair(adbPath: String, address: String, code: String) async throws {
        let res = try await Shell.run(adbPath, ["pair", address, code])
        let combined = res.stdout + "\n" + res.stderr
        if let detail = Self.failureDetail(in: combined) {
            throw WirelessError.pairFailed(detail)
        }
    }

    // MARK: - Connect / Disconnect

    /// Connects to a device already listening for wireless debugging.
    /// A bare host defaults to adb's standard 5555 port.
    func connect(adbPath: String, address: String) async throws {
        let target = address.contains(":") ? address : "\(address):5555"
        let res = try await Shell.run(adbPath, ["connect", target])
        let combined = res.stdout + "\n" + res.stderr
        if let detail = Self.failureDetail(in: combined) {
            throw WirelessError.connectFailed(detail)
        }
    }

    func disconnect(adbPath: String, address: String) async throws {
        _ = try await Shell.run(adbPath, ["disconnect", address])
    }

    // MARK: - Promote USB → Wi-Fi

    /// Switches a USB-attached device to TCP/IP mode and connects to it over the
    /// network, so the cable can be unplugged.
    ///
    /// Returns the `host:port` now serving the device. This is the legacy
    /// (pre-Android 11) flow, which needs no pairing code but does require the
    /// device to currently be on USB.
    @discardableResult
    func enableWirelessDebugging(adbPath: String, serial: String, port: Int = 5555) async throws -> String {
        // `tcpip` restarts adbd on the device, which briefly drops the connection.
        _ = try await Shell.run(adbPath, ["-s", serial, "tcpip", "\(port)"])
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let info = try await inspect(adbPath: adbPath, serial: serial)
        guard let ip = info.ipAddress, !ip.isEmpty else {
            throw WirelessError.noAddress
        }

        let address = "\(ip):\(port)"
        try await connect(adbPath: adbPath, address: address)
        return address
    }
}
