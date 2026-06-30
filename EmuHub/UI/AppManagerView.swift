//
//  AppManagerView.swift
//  EmuHub
//

import SwiftUI

// MARK: - App Manager (in-popover page)

struct AppManagerView: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice
    @State private var search = ""

    private var filtered: [String] {
        guard !search.isEmpty else { return state.packages }
        return state.packages.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                GlassIconTile(systemImage: "square.grid.2x2", color: .blue, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Manage Apps")
                        .font(.system(size: 13, weight: .semibold))
                    Text(device.displayName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { state.closeAppManager() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            // Search
            if !state.packages.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("Filter packages…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            // Content
            Group {
                if state.isLoadingPackages {
                    centeredMessage { ProgressView(); Text("Loading installed apps…") }
                } else if let err = state.packagesError {
                    centeredMessage {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22)).foregroundStyle(.orange)
                        Text(err).multilineTextAlignment(.center)
                    }
                } else if state.packages.isEmpty {
                    centeredMessage {
                        Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(.tertiary)
                        Text("No user-installed apps found")
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 5) {
                            ForEach(filtered, id: \.self) { pkg in
                                PackageRow(device: device, package: pkg)
                                    .environmentObject(state)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(Color(NSColor.windowBackgroundColor))
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [Color.blue.opacity(0.05), .clear, Color.purple.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func centeredMessage<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 10) {
            content()
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct PackageRow: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice
    let package: String
    @State private var hovered = false

    private var isBusy: Bool { state.busyPackage == package }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue.opacity(0.7))
                .frame(width: 18)

            Text(package)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    Button { Task { await state.launchApp(device: device, package: package) } } label: {
                        Label("Launch", systemImage: "play.fill")
                    }
                    Button { Task { await state.forceStopApp(device: device, package: package) } } label: {
                        Label("Force Stop", systemImage: "stop.fill")
                    }
                    Button { Task { await state.clearAppData(device: device, package: package) } } label: {
                        Label("Clear Data", systemImage: "trash")
                    }
                    Divider()
                    Button(role: .destructive) {
                        Task { await state.uninstallApp(device: device, package: package) }
                    } label: {
                        Label("Uninstall", systemImage: "xmark.bin")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(hovered ? .primary : .secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GlassCard(cornerRadius: 9, elevated: hovered))
        .onHover { hovered = $0 }
    }
}

