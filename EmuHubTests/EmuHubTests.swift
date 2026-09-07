//
//  EmuHubTests.swift
//  EmuHubTests
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import Testing
import Foundation
@testable import EmuHub

// Every type in EmuHub is main-actor isolated (the target builds with
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor), while swift-testing runs test
// functions as nonisolated by default. Annotating each suite with @MainActor is
// what lets these tests touch the app's types at all.

// MARK: - ADBParser tests

@MainActor
struct ADBParserTests {

    // MARK: parseLine

    @Test("parseLine handles emulator serial with many spaces before state")
    func parseLineEmulator() throws {
        let line = "emulator-5554          device product:sdk_gphone16k_arm64 model:sdk_gphone16k_arm64 device:emu64a16k transport_id:1"
        let parsed = try #require(ADBParser.parseLine(line))
        #expect(parsed.serial == "emulator-5554")
        #expect(parsed.state  == "device")
        #expect(parsed.metadata["transport_id"] == "1")
        #expect(parsed.metadata["model"] == "sdk_gphone16k_arm64")
    }

    @Test("parseLine handles TLS wireless serial without duplicate suffix")
    func parseLineTLSClean() throws {
        let line = "adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp device product:m12dd model:SM_M127G device:m12 transport_id:76"
        let parsed = try #require(ADBParser.parseLine(line))
        #expect(parsed.rawSerial == "adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp")
        #expect(parsed.serial    == "adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp")
        #expect(parsed.state     == "device")
        #expect(parsed.transportID == 76)
    }

    @Test("parseLine normalizes TLS serial with space and (N) suffix")
    func parseLineTLSDuplicate() throws {
        let line = "adb-A1B2C3D4E5F-x7Yz9W (2)._adb-tls-connect._tcp device product:m12dd model:SM_M127G device:m12 transport_id:77"
        let parsed = try #require(ADBParser.parseLine(line))
        #expect(parsed.rawSerial == "adb-A1B2C3D4E5F-x7Yz9W (2)._adb-tls-connect._tcp")
        // Normalized — space and (2) removed
        #expect(parsed.serial    == "adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp")
        #expect(parsed.state     == "device")
        #expect(parsed.transportID == 77)
    }

    @Test("parseLine handles legacy IP:port Wi-Fi serial")
    func parseLineIPPort() throws {
        let line = "192.168.1.10:5555 device product:xxx model:yyy device:zzz"
        let parsed = try #require(ADBParser.parseLine(line))
        #expect(parsed.serial == "192.168.1.10:5555")
        #expect(parsed.state  == "device")
    }

    @Test("parseLine handles plain alphanumeric USB serial")
    func parseLineUSB() throws {
        let line = "A1B2C3D4E5F device product:m12dd model:SM_M127G device:m12"
        let parsed = try #require(ADBParser.parseLine(line))
        #expect(parsed.serial == "A1B2C3D4E5F")
        #expect(parsed.state  == "device")
    }

    @Test("parseLine handles offline state")
    func parseLineOffline() throws {
        let line = "A1B2C3D4E5F offline"
        let parsed = try #require(ADBParser.parseLine(line))
        #expect(parsed.serial == "A1B2C3D4E5F")
        #expect(parsed.state  == "offline")
        #expect(parsed.metadata.isEmpty)
    }

    @Test("parseLine handles unauthorized state")
    func parseLineUnauthorized() throws {
        let parsed = try #require(ADBParser.parseLine("ABC123 unauthorized"))
        #expect(parsed.state == "unauthorized")
    }

    @Test("parseLine does not misread device: metadata token as state")
    func parseLineDeviceMetadataNotMisread() throws {
        // `device:m12` must not be matched as the adb state
        let line = "A1B2C3D4E5F device product:m12dd device:m12 transport_id:5"
        let parsed = try #require(ADBParser.parseLine(line))
        #expect(parsed.serial == "A1B2C3D4E5F")
        #expect(parsed.state  == "device")
        #expect(parsed.metadata["device"] == "m12")
    }

    @Test("parseLine returns nil for header line")
    func parseLineHeader() {
        #expect(ADBParser.parseLine("List of devices attached") == nil)
    }

    @Test("parseLine returns nil for blank line")
    func parseLineBlank() {
        #expect(ADBParser.parseLine("") == nil)
        #expect(ADBParser.parseLine("   ") == nil)
    }

    @Test("parseLine returns nil for unrecognised line")
    func parseLineUnrecognised() {
        #expect(ADBParser.parseLine("* daemon started successfully") == nil)
    }

    // MARK: parseOutput

    @Test("parseOutput parses realistic adb devices -l output")
    func parseOutput() {
        let stdout = """
        List of devices attached
        adb-A1B2C3D4E5F-x7Yz9W (2)._adb-tls-connect._tcp device product:m12dd model:SM_M127G device:m12 transport_id:77
        adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp device product:m12dd model:SM_M127G device:m12 transport_id:76
        emulator-5554          device product:sdk_gphone16k_arm64 model:sdk_gphone16k_arm64 device:emu64a16k transport_id:1
        """
        let lines = ADBParser.parseOutput(stdout)
        #expect(lines.count == 3)
        #expect(lines[0].rawSerial == "adb-A1B2C3D4E5F-x7Yz9W (2)._adb-tls-connect._tcp")
        #expect(lines[1].rawSerial == "adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp")
        #expect(lines[2].serial    == "emulator-5554")
    }

    // MARK: normalizeSerial

    @Test("normalizeSerial strips (N) from TLS serial")
    func normalizeSerialWithSuffix() {
        #expect(ADBParser.normalizeSerial("adb-XYZ (2)._adb-tls-connect._tcp")
            == "adb-XYZ._adb-tls-connect._tcp")
    }

    @Test("normalizeSerial strips (10) from TLS serial")
    func normalizeSerialHighNumber() {
        #expect(ADBParser.normalizeSerial("adb-XYZ (10)._adb-tls-connect._tcp")
            == "adb-XYZ._adb-tls-connect._tcp")
    }

    @Test("normalizeSerial is a no-op for clean TLS serial")
    func normalizeSerialClean() {
        let s = "adb-XYZ._adb-tls-connect._tcp"
        #expect(ADBParser.normalizeSerial(s) == s)
    }

    @Test("normalizeSerial is a no-op for emulator serial")
    func normalizeSerialEmulator() {
        #expect(ADBParser.normalizeSerial("emulator-5554") == "emulator-5554")
    }

    @Test("normalizeSerial is a no-op for USB serial")
    func normalizeSerialUSB() {
        #expect(ADBParser.normalizeSerial("A1B2C3D4E5F") == "A1B2C3D4E5F")
    }

    @Test("normalizeSerial is a no-op for IP:port serial")
    func normalizeSerialIPPort() {
        #expect(ADBParser.normalizeSerial("192.168.1.5:5555") == "192.168.1.5:5555")
    }

    // MARK: deduplicate

    @Test("deduplicate keeps higher transport_id winner")
    func deduplicateKeepsHigherTransportID() throws {
        let stdout = """
        List of devices attached
        adb-A1B2C3D4E5F-x7Yz9W (2)._adb-tls-connect._tcp device transport_id:77
        adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp device transport_id:76
        emulator-5554 device transport_id:1
        """
        let parsed = ADBParser.parseOutput(stdout)
        let deduped = ADBParser.deduplicate(parsed)

        #expect(deduped.count == 2)
        // The (2) variant has transport_id 77 > 76, so it wins
        let wireless = try #require(deduped.first)
        #expect(wireless.transportID == 77)
        #expect(wireless.serial == "adb-A1B2C3D4E5F-x7Yz9W._adb-tls-connect._tcp")
        #expect(deduped[1].serial == "emulator-5554")
    }

    @Test("deduplicate preserves first-occurrence order")
    func deduplicatePreservesOrder() {
        let stdout = """
        emulator-5554 device transport_id:1
        adb-XYZ (2)._adb-tls-connect._tcp device transport_id:5
        adb-XYZ._adb-tls-connect._tcp device transport_id:4
        """
        let deduped = ADBParser.deduplicate(ADBParser.parseOutput(stdout))
        #expect(deduped.count == 2)
        #expect(deduped[0].serial == "emulator-5554")
        #expect(deduped[1].serial == "adb-XYZ._adb-tls-connect._tcp")
    }

    @Test("deduplicate is a no-op when all serials are unique")
    func deduplicateNoDuplicates() {
        let stdout = """
        emulator-5554 device transport_id:1
        A1B2C3D4E5F device transport_id:2
        """
        let parsed = ADBParser.parseOutput(stdout)
        let deduped = ADBParser.deduplicate(parsed)
        #expect(deduped.count == parsed.count)
    }
}

// MARK: - RunningDevice classification tests

@MainActor
struct RunningDeviceClassificationTests {

    @Test("connectionType is .wifi for TLS wireless serial")
    func connectionTypeTLS() {
        let d = RunningDevice(serial: "adb-XYZ._adb-tls-connect._tcp", state: "device")
        #expect(d.connectionType == .wifi)
    }

    @Test("connectionType is .wifi for IPv4:port serial")
    func connectionTypeIPv4() {
        let d = RunningDevice(serial: "192.168.1.5:5555", state: "device")
        #expect(d.connectionType == .wifi)
    }

    @Test("connectionType is .wifi for IPv6:port serial")
    func connectionTypeIPv6() {
        let d = RunningDevice(serial: "[::1]:5555", state: "device")
        #expect(d.connectionType == .wifi)
    }

    @Test("connectionType is .usb for alphanumeric USB serial")
    func connectionTypeUSB() {
        let d = RunningDevice(serial: "A1B2C3D4E5F", state: "device")
        #expect(d.connectionType == .usb)
    }

    @Test("connectionType is .usb for emulator serial")
    func connectionTypeEmulator() {
        let d = RunningDevice(serial: "emulator-5554", state: "device")
        #expect(d.connectionType == .usb)
    }

    @Test("kind is .emulator for emulator- prefix")
    func kindEmulator() {
        #expect(RunningDevice(serial: "emulator-5554", state: "device").kind == .emulator)
    }

    @Test("kind is .physical for TLS wireless serial")
    func kindPhysicalTLS() {
        let d = RunningDevice(serial: "adb-XYZ._adb-tls-connect._tcp", state: "device")
        #expect(d.kind == .physical)
    }
}

// MARK: - Original tests

@MainActor
struct EmuHubTests {

    @Test("RunningDevice classifies emulators by serial prefix")
    func runningDeviceClassifiesKindsCorrectly() {
        let emulator = RunningDevice(serial: "emulator-5554", state: "device")
        let phone = RunningDevice(serial: "R58M123456", state: "device")

        #expect(emulator.kind == .emulator)
        #expect(emulator.isEmulator)
        #expect(phone.kind == .physical)
        #expect(!phone.isEmulator)
    }

    @Test("RunningDevice exposes unauthorized and offline states")
    func runningDeviceStateFlags() {
        let unauthorized = RunningDevice(serial: "ABC123", state: "unauthorized")
        let offline = RunningDevice(serial: "ABC123", state: "offline")
        let connected = RunningDevice(serial: "ABC123", state: "device")

        #expect(unauthorized.isUnauthorized)
        #expect(!unauthorized.isOffline)

        #expect(offline.isOffline)
        #expect(!offline.isUnauthorized)

        #expect(!connected.isUnauthorized)
        #expect(!connected.isOffline)
    }

    @Test("AndroidToolchain.defaultMacSdkPath points under user Library")
    func defaultSdkPathLooksReasonable() {
        let path = AndroidToolchain.defaultMacSdkPath()
        #expect(path.hasSuffix("/Library/Android/sdk"))
    }

    @Test("ReleaseUpdateService normalizes tags and compares semantic versions")
    func releaseVersionComparison() {
        let normalized = ReleaseUpdateService.normalizedVersion(from: "v1.2.3")
        #expect(normalized == "1.2.3")

        #expect(ReleaseUpdateService.compareVersion("1.2.3", "1.2.4") == .orderedAscending)
        #expect(ReleaseUpdateService.compareVersion("1.2.4", "1.2.3") == .orderedDescending)
        #expect(ReleaseUpdateService.compareVersion("1.2.0", "1.2") == .orderedSame)
    }

    @Test("ReleaseUpdateService ignores metadata suffixes for equality checks")
    func releaseVersionMetadataIsIgnored() {
        #expect(ReleaseUpdateService.normalizedVersion(from: "v1.2.3+45") == "1.2.3")
        #expect(ReleaseUpdateService.normalizedVersion(from: "1.2.3-beta") == "1.2.3")
        #expect(ReleaseUpdateService.compareVersion("1.2.3", "1.2.3+45") == .orderedSame)
    }
}

// MARK: - Device inspection parsing

@MainActor
struct DeviceInspectionTests {

    /// Representative output of the single combined shell call the inspector makes.
    private let sample = """
    __EH_PROPS__
    Google
    Pixel 8 Pro
    14
    34
    arm64-v8a
    __EH_BATTERY__
    Current Battery Service state:
      AC powered: false
      level: 87
      status: 3
      temperature: 305
    __EH_DISPLAY__
    Physical size: 1008x2244
    Physical density: 420
    __EH_STORAGE__
    Filesystem     1K-blocks     Used Available Use% Mounted on
    /dev/block/dm-5 118293240 41264180  76029060  36% /data
    __EH_NET__
    192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42
    __EH_UPTIME__
    93784.21 41234.10
    """

    @Test("parseInspection reads properties, battery, display, storage, network, and uptime")
    func parsesEverySection() throws {
        let info = AdbService.parseInspection(sample)

        #expect(info.manufacturer == "Google")
        #expect(info.model == "Pixel 8 Pro")
        #expect(info.androidVersion == "14")
        #expect(info.sdkInt == "34")
        #expect(info.abi == "arm64-v8a")

        #expect(info.batteryLevel == 87)
        #expect(info.batteryStatus == .discharging)
        // dumpsys reports tenths of a degree.
        #expect(info.batteryTemperature == 30.5)

        #expect(info.resolutionWidth == 1008)
        #expect(info.resolutionHeight == 2244)
        #expect(info.density == 420)

        // df reports 1K blocks, so the parser scales both columns to bytes.
        #expect(try #require(info.storageTotalBytes) == Int64(118_293_240) * 1024)
        #expect(try #require(info.storageUsedBytes) == Int64(41_264_180) * 1024)

        #expect(info.ipAddress == "192.168.1.42")
        #expect(info.uptimeSeconds == 93784.21)
    }

    @Test("parseInspection prefers an override display size over the physical one")
    func overrideSizeWins() {
        let output = """
        __EH_DISPLAY__
        Physical size: 1440x3120
        Override size: 1080x2340
        Physical density: 560
        Override density: 420
        """
        let info = AdbService.parseInspection(output)
        #expect(info.resolutionWidth == 1080)
        #expect(info.resolutionHeight == 2340)
        #expect(info.density == 420)
    }

    @Test("parseInspection degrades field by field when sections are missing")
    func partialOutputStillParses() {
        let output = """
        __EH_PROPS__
        Samsung
        SM-S911B
        13
        33
        arm64-v8a
        __EH_BATTERY__
        __EH_STORAGE__
        """
        let info = AdbService.parseInspection(output)
        #expect(info.model == "SM-S911B")
        #expect(info.batteryLevel == nil)
        #expect(info.storageTotalBytes == nil)
        #expect(info.ipAddress == nil)
    }

    @Test("Formatted values render only when their source data is present")
    func formattedValues() {
        var info = DeviceInfo()
        #expect(info.batteryText == nil)
        #expect(info.storageText == nil)
        #expect(info.resolutionText == nil)

        info.batteryLevel = 45
        info.batteryStatus = .charging
        #expect(info.batteryText == "45% · Charging")

        info.resolutionWidth = 1080
        info.resolutionHeight = 2400
        info.density = 440
        #expect(info.resolutionText == "1080 × 2400 · 440 dpi")

        info.androidVersion = "14"
        info.sdkInt = "34"
        #expect(info.osText == "Android 14 · API 34")

        info.storageTotalBytes = 1000
        info.storageUsedBytes = 250
        #expect(info.storageFraction == 0.25)
    }

    @Test("Uptime is summarised at the largest useful unit")
    func uptimeFormatting() {
        var info = DeviceInfo()
        info.uptimeSeconds = 90
        #expect(info.uptimeText == "1m")
        info.uptimeSeconds = 3_700
        #expect(info.uptimeText == "1h 1m")
        info.uptimeSeconds = 93_784
        #expect(info.uptimeText == "1d 2h")
    }
}

// MARK: - Recording size capping

@MainActor
struct RecordingSizeTests {

    @Test("Recording size is left alone when it already fits the cap")
    func belowCapIsUnchanged() {
        #expect(AdbService.cappedRecordingSize(width: 720, height: 1280) == "720x1280")
    }

    @Test("Oversized displays are scaled down preserving aspect ratio and even dimensions")
    func aboveCapIsScaled() {
        let size = AdbService.cappedRecordingSize(width: 1280, height: 2856)
        let parts = size.split(separator: "x").compactMap { Int($0) }
        #expect(parts.count == 2)
        #expect(max(parts[0], parts[1]) == 1280)
        // screenrecord's encoder rejects odd dimensions.
        #expect(parts[0] % 2 == 0)
        #expect(parts[1] % 2 == 0)
    }
}
