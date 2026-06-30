//
//  CreateAVDView.swift
//  EmuHub
//

import SwiftUI

// MARK: - Create AVD View

struct CreateAVDView: View {
    @EnvironmentObject var state: AppState

    @State private var avdName: String = ""
    @State private var systemImages: [SystemImage] = []
    @State private var deviceProfiles: [DeviceProfile] = []
    @State private var selectedImage: SystemImage?
    @State private var selectedDevice: DeviceProfile?
    @State private var isLoading = true
    @State private var loadError: String?

    private var sanitizedName: String {
        avdName.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "_")
    }

    private var canCreate: Bool {
        !sanitizedName.isEmpty && selectedImage != nil && selectedDevice != nil && !state.isCreatingAVD
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {

                if let err = state.avdCreationError {
                    ErrorBanner(message: err)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading SDK data…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if let err = loadError {
                    ErrorBanner(message: err)
                } else {
                    // Name
                    CreateAVDSection(title: "Name", icon: "character.cursor.ibeam") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("e.g. Pixel_9_API_35", text: $avdName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .glassField()
                            if !avdName.isEmpty && avdName.contains(" ") {
                                Text("Spaces will be replaced with underscores: \(sanitizedName)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // System Image
                    CreateAVDSection(title: "System Image", icon: "cpu") {
                        if systemImages.isEmpty {
                            Text("No system images installed. Use SDK Manager to install one.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(systemImages) { img in
                                    SelectionRow(
                                        label: img.displayName,
                                        detail: img.packageName,
                                        isSelected: selectedImage == img
                                    ) { selectedImage = img }
                                }
                            }
                        }
                    }

                    // Device Profile
                    CreateAVDSection(title: "Hardware Profile", icon: "iphone") {
                        if deviceProfiles.isEmpty {
                            Text("No device profiles found.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            // Show a picker since profiles list is long
                            Picker("", selection: $selectedDevice) {
                                Text("Select a device…").tag(Optional<DeviceProfile>.none)
                                ForEach(deviceProfiles) { profile in
                                    Text(profile.name).tag(Optional(profile))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Create button
                    Button {
                        guard let img = selectedImage, let dev = selectedDevice else { return }
                        Task {
                            await state.createAVD(
                                name: sanitizedName,
                                systemImagePackage: img.packageName,
                                deviceId: dev.deviceId
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if state.isCreatingAVD {
                                ProgressView().controlSize(.small)
                                Text("Creating…")
                            } else {
                                Image(systemName: "plus.circle.fill")
                                Text("Create AVD")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(canCreate ? Color.blue : Color.secondary.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .padding(.top, 4)
                }

                Spacer(minLength: 14)
            }
            .padding(16)
        }
        .task { await loadData() }
        .onChange(of: state.isCreatingAVD) { _, creating in
            // Clear error when a new creation starts
            if creating { state.avdCreationError = nil }
        }
    }

    private func loadData() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let sdkPath = state.sdkPath
            // System images: filesystem scan (synchronous, fast)
            systemImages = state.emulatorService.listSystemImages(sdkPath: sdkPath)

            // Device profiles: requires avdmanager
            let toolchain = try AndroidToolchain(sdkPath: sdkPath)
            guard let avdmanagerPath = toolchain.avdmanagerPath else {
                loadError = "avdmanager not found. Install Android Command-line Tools via SDK Manager."
                deviceProfiles = []
                return
            }
            deviceProfiles = try await state.emulatorService.listDeviceProfiles(avdmanagerPath: avdmanagerPath)
            // Pre-select sensible defaults
            selectedImage = systemImages.first
            selectedDevice = deviceProfiles.first { $0.deviceId == "pixel_7" }
                ?? deviceProfiles.first { $0.name.lowercased().contains("pixel") }
                ?? deviceProfiles.first
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct CreateAVDSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
            }
            content()
        }
    }
}

private struct SelectionRow: View {
    let label: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.blue : Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.07) : (hovered ? Color.primary.opacity(0.04) : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}

