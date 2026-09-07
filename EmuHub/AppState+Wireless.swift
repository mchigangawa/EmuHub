//
//  AppState+Wireless.swift
//  EmuHub
//
//  Wireless debugging: pair with a code, connect to an address, drop a wireless
//  device, and promote a USB device onto the network.
//

import Foundation
import SwiftUI

extension AppState {

    func openWirelessSheet() {
        wirelessError = nil
        wirelessSuccess = nil
        isWirelessSheetOpen = true
    }

    func closeWirelessSheet() {
        isWirelessSheetOpen = false
        wirelessError = nil
        wirelessSuccess = nil
    }

    /// Pairs with a device using the address and six-digit code from the device's
    /// Wireless debugging screen, then connects on the separate connect port.
    ///
    /// Pairing alone does not attach the device — Android exposes one port for
    /// pairing and a different one for the debugging connection — so a connect
    /// address is required to finish the flow.
    func pairAndConnect(pairAddress: String, code: String, connectAddress: String) async {
        let pairTarget = pairAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let connectTarget = connectAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairingCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pairTarget.isEmpty, !pairingCode.isEmpty else {
            wirelessError = "Enter the pairing address and code shown on your device."
            return
        }

        await runWirelessAction {
            let toolchain = try AndroidToolchain(sdkPath: self.sdkPath)
            try await self.adbService.pair(
                adbPath: toolchain.adbPath, address: pairTarget, code: pairingCode
            )

            guard !connectTarget.isEmpty else {
                return "Paired. Now enter the connect address to attach the device."
            }

            try await self.adbService.connect(adbPath: toolchain.adbPath, address: connectTarget)
            return "Connected to \(connectTarget)"
        }
    }

    /// Connects to a device that has already been paired with this Mac.
    func connectWireless(address: String) async {
        let target = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            wirelessError = "Enter an address like 192.168.1.42:5555."
            return
        }

        await runWirelessAction {
            let toolchain = try AndroidToolchain(sdkPath: self.sdkPath)
            try await self.adbService.connect(adbPath: toolchain.adbPath, address: target)
            return "Connected to \(target)"
        }
    }

    /// Switches a USB-attached device to wireless so the cable can be unplugged.
    func enableWirelessDebugging(device: RunningDevice) async {
        busyDevices.insert(device.serial)
        defer { busyDevices.remove(device.serial) }

        await runWirelessAction {
            let toolchain = try AndroidToolchain(sdkPath: self.sdkPath)
            let address = try await self.adbService.enableWirelessDebugging(
                adbPath: toolchain.adbPath, serial: device.serial
            )
            return "Wireless debugging on at \(address) — you can unplug the cable."
        }
    }

    /// Disconnects a wireless device. USB devices are unaffected, so this is only
    /// offered for `.wifi` connections.
    func disconnectWireless(device: RunningDevice) async {
        guard device.connectionType == .wifi else { return }

        await runWirelessAction {
            let toolchain = try AndroidToolchain(sdkPath: self.sdkPath)
            try await self.adbService.disconnect(adbPath: toolchain.adbPath, address: device.serial)
            return "Disconnected \(device.displayName)"
        }
    }

    // MARK: - Shared Runner

    /// Runs a wireless action, publishing its success message or error into the
    /// sheet, and refreshing the device list either way so the result is visible.
    private func runWirelessAction(_ action: @escaping () async throws -> String) async {
        isWirelessBusy = true
        wirelessError = nil
        wirelessSuccess = nil
        defer { isWirelessBusy = false }

        do {
            ensureSdkPath()
            let message = try await action()
            wirelessSuccess = message
            setActionFeedback(message)
        } catch {
            wirelessError = error.localizedDescription
        }

        await refreshAll()
    }
}
