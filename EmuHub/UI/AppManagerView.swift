//
//  AppManagerView.swift
//  EmuHub
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Manager (in-popover panel)

struct AppManagerView: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice

    @State private var search = ""
    @State private var isDropTargeted = false

    private var filtered: [String] {
        guard !search.isEmpty else { return state.packages }
        return state.packages.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                icon: "square.grid.2x2",
                tint: Theme.Palette.physical,
                title: "Manage Apps",
                subtitle: device.displayName,
                onClose: { state.closeAppManager() }
            ) {
                if !state.packages.isEmpty {
                    CountBadge(count: state.packages.count, tint: Theme.Palette.physical)
                }

                IconButton(systemImage: "arrow.clockwise", help: "Reload apps", size: 24, symbolSize: 11) {
                    Task { await state.loadPackages(for: device) }
                }
                .disabled(state.isLoadingPackages)
                .opacity(state.isLoadingPackages ? 0.4 : 1)
            }

            Hairline(inset: 0).opacity(0.5)

            if !state.packages.isEmpty {
                SearchField(
                    text: $search,
                    placeholder: "Filter packages…",
                    shape: .capsule
                )
                .pageGutter()
                .padding(.top, Theme.Space.md)
            }

            content
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground(tint: Theme.Palette.physical) }
        .overlay { dropOverlay }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoadingPackages && state.packages.isEmpty {
            PanelMessage(showsProgress: true, message: "Loading installed apps…")
        } else if let error = state.packagesError {
            PanelMessage(
                systemImage: "exclamationmark.triangle",
                message: error,
                tint: Theme.Palette.warning
            )
        } else if state.packages.isEmpty {
            PanelMessage(
                systemImage: "tray",
                message: "No user-installed apps found.\nDrop an .apk here to install one."
            )
        } else if filtered.isEmpty {
            PanelMessage(systemImage: "magnifyingglass", message: "No packages match “\(search)”")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 5) {
                    ForEach(filtered, id: \.self) { package in
                        PackageRow(device: device, package: package)
                            .environmentObject(state)
                    }
                }
                .padding(Theme.Space.gutter)
            }
        }
    }

    /// The panel accepts APK drops too, so you don't have to close it and find
    /// the device card just to install a build.
    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                VStack(spacing: Theme.Space.md) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Palette.accent)
                    Text("Drop to install on \(device.displayName)")
                        .font(.ehBody)
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            } else {
                url = nil
            }
            guard let fileURL = url, fileURL.pathExtension.lowercased() == "apk" else { return }
            Task { @MainActor in
                await state.installAPK(device: device, url: fileURL)
                await state.loadPackages(for: device)
            }
        }
        return true
    }
}

// MARK: - Package Row

private struct PackageRow: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice
    let package: String

    @State private var hovered = false
    @State private var confirmingUninstall = false

    private var isBusy: Bool { state.busyPackage == package }

    /// Package names are long and front-loaded with the reverse-domain prefix,
    /// so the last component is what actually identifies the app at a glance.
    private var shortName: String {
        package.split(separator: ".").last.map(String.init) ?? package
    }

    private var namespace: String {
        let parts = package.split(separator: ".")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: ".")
    }

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.physical.opacity(0.7))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(shortName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !namespace.isEmpty {
                    Text(namespace)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Theme.Space.sm)

            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                if hovered {
                    IconButton(systemImage: "play.fill", help: "Launch", size: 22, symbolSize: 9) {
                        Task { await state.launchApp(device: device, package: package) }
                    }
                    .transition(.opacity)
                }

                Menu {
                    Button { Task { await state.launchApp(device: device, package: package) } } label: {
                        Label("Launch", systemImage: "play.fill")
                    }
                    Button { Task { await state.forceStopApp(device: device, package: package) } } label: {
                        Label("Force Stop", systemImage: "stop.fill")
                    }
                    Button { Task { await state.openAppSettings(device: device, package: package) } } label: {
                        Label("Open App Info on Device", systemImage: "gearshape")
                    }

                    Divider()

                    Button { state.copyToClipboard(package, feedback: "Package name copied") } label: {
                        Label("Copy Package Name", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task { await state.clearAppData(device: device, package: package) }
                    } label: {
                        Label("Clear Data", systemImage: "trash")
                    }
                    Button(role: .destructive) {
                        confirmingUninstall = true
                    } label: {
                        Label("Uninstall…", systemImage: "xmark.bin")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(hovered ? .primary : .secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .tooltip("App actions")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Theme.Space.md)
        .background(GlassCard(cornerRadius: Theme.Radius.sm, elevated: hovered))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(Theme.Motion.snappy, value: hovered)
        .help(package)
        .confirmationDialog(
            "Uninstall \(shortName)?",
            isPresented: $confirmingUninstall,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await state.uninstallApp(device: device, package: package) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("\(package) and all of its data will be removed from \(device.displayName).")
        }
    }
}
