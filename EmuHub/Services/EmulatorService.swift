//
//  EmulatorService.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import Foundation

// MARK: - AVD Creation Models

struct DeviceProfile: Identifiable, Hashable {
    var id: String { deviceId }
    let deviceId: String
    let name: String
}

struct SystemImage: Identifiable, Hashable {
    var id: String { packageName }
    let apiLevel: Int
    let tag: String   // e.g. "google_apis", "google_apis_playstore", "default"
    let abi: String   // e.g. "arm64-v8a", "x86_64"

    var packageName: String { "system-images;android-\(apiLevel);\(tag);\(abi)" }

    var tagDisplayName: String {
        switch tag {
        case "google_apis":           return "Google APIs"
        case "google_apis_playstore": return "Google Play"
        case "default":               return "AOSP"
        default:                      return tag.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var displayName: String { "API \(apiLevel) · \(tagDisplayName) · \(abi)" }
}

// MARK: - Service

struct EmulatorService {
    func listAVDs(emulatorPath: String) async throws -> [String] {
        let res = try await Shell.run(emulatorPath, ["-list-avds"])
        return res.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    // MARK: - AVD Creation

    /// Scans `$SDK/system-images/` for installed system images without spawning a process.
    func listSystemImages(sdkPath: String) -> [SystemImage] {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: sdkPath).appendingPathComponent("system-images")
        guard let apiDirs = try? fm.contentsOfDirectory(atPath: base.path) else { return [] }

        var images: [SystemImage] = []
        for apiDir in apiDirs where apiDir.hasPrefix("android-") {
            guard let level = Int(apiDir.dropFirst("android-".count)) else { continue }
            let apiURL = base.appendingPathComponent(apiDir)
            guard let tags = try? fm.contentsOfDirectory(atPath: apiURL.path) else { continue }
            for tag in tags {
                let tagURL = apiURL.appendingPathComponent(tag)
                guard let abis = try? fm.contentsOfDirectory(atPath: tagURL.path) else { continue }
                for abi in abis {
                    // Confirm it's a real image directory (has source.properties)
                    let props = tagURL.appendingPathComponent(abi).appendingPathComponent("source.properties")
                    guard fm.fileExists(atPath: props.path) else { continue }
                    images.append(SystemImage(apiLevel: level, tag: tag, abi: abi))
                }
            }
        }
        // Newest API level first, then stable tags before playstore/default, then prefer arm64
        return images.sorted {
            if $0.apiLevel != $1.apiLevel { return $0.apiLevel > $1.apiLevel }
            if $0.tag != $1.tag { return $0.tag < $1.tag }
            return $0.abi < $1.abi
        }
    }

    /// Parses `avdmanager list device` output into device profile pairs.
    func listDeviceProfiles(avdmanagerPath: String) async throws -> [DeviceProfile] {
        let res = try await Shell.run(avdmanagerPath, ["list", "device"])
        var profiles: [DeviceProfile] = []
        var pendingId: String?
        for raw in res.stdout.split(whereSeparator: \.isNewline).map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("id:") {
                // Extract the quoted ID: id: 0 or "pixel_7"
                if let first = line.firstIndex(of: "\""),
                   let last = line.lastIndex(of: "\""),
                   first < last {
                    let start = line.index(after: first)
                    pendingId = String(line[start..<last])
                }
            } else if line.hasPrefix("Name:"), let deviceId = pendingId {
                let name = line.dropFirst("Name:".count).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    profiles.append(DeviceProfile(deviceId: deviceId, name: name))
                }
                pendingId = nil
            }
        }
        return profiles
    }

    /// Creates an AVD. Pipes a newline to stdin to skip the hardware profile prompt.
    func createAVD(avdmanagerPath: String, name: String, package: String, device: String) async throws {
        let stdin = "\n".data(using: .utf8)
        _ = try await Shell.run(
            avdmanagerPath,
            ["create", "avd", "--name", name, "--package", package, "--device", device],
            stdin: stdin
        )
    }

    /// Deletes an AVD and its data via `avdmanager delete avd`.
    func deleteAVD(avdmanagerPath: String, name: String) async throws {
        _ = try await Shell.run(avdmanagerPath, ["delete", "avd", "--name", name])
    }

    func startAVD(emulatorPath: String, avdName: String, extraArgs: [String]) async throws {
        // Start and detach: we intentionally don't await termination
        let process = Process()
        process.executableURL = URL(fileURLWithPath: emulatorPath)
        process.arguments = ["-avd", avdName] + extraArgs

        // Optional: prevent it from spamming your app logs
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
    }
}
