//
//  MenuBarRootView.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Navigation Route

enum AppRoute: Hashable {
    case settings, help, about, updates, createAVD

    /// Routes that appear in the hamburger menu dropdown.
    static let menuItems: [AppRoute] = [.settings, .help, .about, .updates]

    var title: String {
        switch self {
        case .settings:  "Settings"
        case .help:      "Help"
        case .about:     "About EmuHub"
        case .updates:   "Software Update"
        case .createAVD: "New AVD"
        }
    }

    var systemImage: String {
        switch self {
        case .settings:  "gearshape"
        case .help:      "questionmark.circle"
        case .about:     "info.circle"
        case .updates:   "arrow.trianglehead.2.clockwise.rotate.90.circle"
        case .createAVD: "plus.circle.fill"
        }
    }
}

// MARK: - Root

struct MenuBarRootView: View {
    @EnvironmentObject var state: AppState
    @State private var route: AppRoute?
    @State private var menuOpen = false

    var body: some View {
        VStack(spacing: 0) {
            AppNavBar(
                route: route,
                menuOpen: $menuOpen,
                onBack: goBack,
                onNavigate: navigate(to:)
            )

            Divider().opacity(0.07)

            ZStack {
                if route == nil {
                    HomeView(onNavigate: navigate(to:))
                        .environmentObject(state)
                        .transition(.push(from: .leading))
                        .zIndex(0)
                } else {
                    PageView(route: route!)
                        .environmentObject(state)
                        .transition(.push(from: .trailing))
                        .zIndex(1)
                        .id(route)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: route)
        }
        .frame(width: 420, height: 620)
        .background {
            VisualEffectBackground(material: .menu, blendingMode: .behindWindow)
                .overlay(
                    // Subtle brand wash so the glass reads warm, not flat grey.
                    LinearGradient(
                        colors: [Color.blue.opacity(0.06), .clear, Color.purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()
        }
        .overlay {
            if let device = state.appManagerDevice {
                AppManagerView(device: device)
                    .environmentObject(state)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: state.appManagerDevice)
        .overlay {
            if let device = state.logcatDevice {
                LogcatView(device: device)
                    .environmentObject(state)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(21)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: state.logcatDevice)
        .overlay {
            if menuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .zIndex(9)

                AppMenuDropdown(onNavigate: navigate(to:))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 54)
                    .padding(.trailing, 12)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: menuOpen)
        .task {
            await state.refreshAll()
            state.startAutoRefresh()
        }
        .onDisappear {
            state.stopAutoRefresh()
            // Don't leave a logcat process streaming while the popover is hidden.
            state.closeLogcat()
            menuOpen = false
        }
    }

    private func navigate(to destination: AppRoute) {
        closeMenu()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            route = destination
        }
    }

    private func goBack() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            route = nil
        }
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            menuOpen = false
        }
    }
}

// MARK: - Navigation Bar

private struct AppNavBar: View {
    @EnvironmentObject var state: AppState
    let route: AppRoute?
    @Binding var menuOpen: Bool
    let onBack: () -> Void
    let onNavigate: (AppRoute) -> Void

    var body: some View {
        ZStack {
            if let route {
                Text(route.title)
                    .font(.system(size: 13, weight: .semibold))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            HStack(spacing: 0) {
                if route != nil {
                    NavBackButton(action: onBack)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    AppIdentity()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Spacer()

                if route == nil {
                    HStack(spacing: 8) {
                        StatusPill(running: state.running.count)
                        NavMenuButton(open: $menuOpen)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Color.clear.frame(width: 52)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: route == nil)
    }
}

private struct NavBackButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(hovered ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct AppIdentity: View {
    var body: some View {
        HStack(spacing: 10) {
            AppIconMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("EmuHub")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Android Device Manager")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct AppIconMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    colors: [.blue.opacity(0.15), .purple.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 30, height: 30)

            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
    }
}

private struct StatusPill: View {
    let running: Int

    private var isActive: Bool { running > 0 }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
                .shadow(color: isActive ? .green.opacity(0.45) : .clear, radius: 3)
            Text(isActive ? "\(running) active" : "idle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(
                    isActive ? Color.green.opacity(0.3) : Color.primary.opacity(0.06),
                    lineWidth: 1))
        )
        .animation(.spring(response: 0.3), value: running)
    }
}

private struct NavMenuButton: View {
    @Binding var open: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                open.toggle()
            }
        } label: {
            Image(systemName: open ? "xmark" : "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle((hovered || open) ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill((hovered || open) ? Color.primary.opacity(0.08) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: open)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - App Menu Dropdown

private struct AppMenuDropdown: View {
    let onNavigate: (AppRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AppRoute.menuItems, id: \.self) { route in
                MenuRow(icon: route.systemImage, label: route.title) {
                    onNavigate(route)
                }
                if route != AppRoute.menuItems.last {
                    Divider()
                        .padding(.leading, 38)
                        .opacity(0.35)
                }
            }

            Divider().opacity(0.3).padding(.vertical, 2)

            MenuRow(icon: "power", label: "Quit EmuHub", destructive: true) {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 210)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.20), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct MenuRow: View {
    let icon: String
    let label: String
    var destructive: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(destructive ? .red : .secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(destructive ? .red : .primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Page Router

private struct PageView: View {
    @EnvironmentObject var state: AppState
    let route: AppRoute

    var body: some View {
        switch route {
        case .settings:
            SettingsView(preferredWidth: nil)
                .environmentObject(state)
        case .help:
            HelpView()
        case .about:
            AboutPage()
        case .updates:
            CheckForUpdatesPage()
                .environmentObject(state)
        case .createAVD:
            CreateAVDView()
                .environmentObject(state)
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarRootView()
        .environmentObject(AppState())
}
