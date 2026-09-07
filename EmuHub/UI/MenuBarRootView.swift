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

// MARK: - Overlay Panels

/// The full-bleed panels that slide over the whole popover. Modelling them as
/// one value means only ever one can be on screen, replacing the stack of
/// independently-z-indexed overlays this view used to carry.
private enum Panel: Equatable {
    case inspector(RunningDevice)
    case appManager(RunningDevice)
    case logcat(RunningDevice)
    case wireless
}

// MARK: - Root

struct MenuBarRootView: View {
    @EnvironmentObject var state: AppState
    @State private var route: AppRoute?
    @State private var menuOpen = false

    /// Popover size, persisted so the window comes back the way it was left.
    @AppStorage("popoverWidth") private var popoverWidth: Double = PopoverSize.defaultWidth
    @AppStorage("popoverHeight") private var popoverHeight: Double = PopoverSize.defaultHeight

    private var panel: Panel? {
        // Deepest-first: a panel opened from inside another one wins.
        if let device = state.logcatDevice { return .logcat(device) }
        if let device = state.appManagerDevice { return .appManager(device) }
        if let device = state.inspectorDevice { return .inspector(device) }
        if state.isWirelessSheetOpen { return .wireless }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavBar(
                route: route,
                menuOpen: $menuOpen,
                onBack: goBack,
                onNavigate: navigate(to:)
            )

            Hairline(inset: 0)

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
            .animation(Theme.Motion.page, value: route)
        }
        .frame(width: popoverWidth, height: popoverHeight)
        .background {
            VisualEffectBackground(material: .menu, blendingMode: .behindWindow)
                .overlay(
                    // Subtle brand wash so the glass reads warm, not flat grey.
                    LinearGradient(
                        colors: [
                            Theme.Palette.accent.opacity(0.06),
                            .clear,
                            Theme.Palette.secondaryAccent.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()
        }
        .overlay { panelOverlay }
        .overlay { menuOverlay }
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip(width: $popoverWidth, height: $popoverHeight)
                .padding(.trailing, 2)
                .padding(.bottom, 2)
        }
        // Above every panel and overlay, so hover labels are never clipped by a
        // scroll view or a glass group further down the tree.
        .tooltipLayer()
        .animation(Theme.Motion.smooth, value: panel)
        .animation(Theme.Motion.smooth, value: menuOpen)
        .onExitCommand(perform: handleEscape)
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

    // MARK: Overlays

    @ViewBuilder
    private var panelOverlay: some View {
        if let panel {
            Group {
                switch panel {
                case .inspector(let device):
                    DeviceInspectorView(device: device).environmentObject(state)
                case .appManager(let device):
                    AppManagerView(device: device).environmentObject(state)
                case .logcat(let device):
                    LogcatView(device: device).environmentObject(state)
                case .wireless:
                    WirelessConnectView().environmentObject(state)
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var menuOverlay: some View {
        if menuOpen {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { closeMenu() }

                AppMenuDropdown(onNavigate: navigate(to:))
                    .padding(.top, Theme.Size.navBar)
                    .padding(.trailing, Theme.Space.lg)
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Navigation

    private func navigate(to destination: AppRoute) {
        closeMenu()
        withAnimation(Theme.Motion.page) { route = destination }
    }

    private func goBack() {
        withAnimation(Theme.Motion.page) { route = nil }
    }

    private func closeMenu() {
        withAnimation(Theme.Motion.smooth) { menuOpen = false }
    }

    /// Escape unwinds one level at a time: menu, then panel, then page.
    private func handleEscape() {
        if menuOpen {
            closeMenu()
        } else if let panel {
            switch panel {
            case .logcat:     state.closeLogcat()
            case .appManager: state.closeAppManager()
            case .inspector:  state.closeInspector()
            case .wireless:   state.closeWirelessSheet()
            }
        } else if route != nil {
            goBack()
        }
    }
}

// MARK: - Popover Sizing

enum PopoverSize {
    static let defaultWidth: Double = 420
    static let defaultHeight: Double = 620
    static let minWidth: Double = 380
    static let maxWidth: Double = 760
    static let minHeight: Double = 460
    static let maxHeight: Double = 900

    static func clampWidth(_ value: Double) -> Double {
        min(maxWidth, max(minWidth, value))
    }

    static func clampHeight(_ value: Double) -> Double {
        min(maxHeight, max(minHeight, value))
    }
}

/// Bottom-right drag handle that resizes the popover.
///
/// A `MenuBarExtra(.window)` panel is sized by SwiftUI to fit its content and
/// has no title bar to drag, so an explicit grip is the reliable way to offer
/// resizing — the panel follows the content frame this updates.
private struct ResizeGrip: View {
    @Binding var width: Double
    @Binding var height: Double

    /// Size at the moment the drag began, so the gesture's cumulative
    /// translation is applied to a fixed origin rather than compounding.
    @State private var dragOrigin: CGSize?
    @State private var hovered = false

    var body: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
            .opacity(hovered || dragOrigin != nil ? 1 : 0.35)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let origin = dragOrigin ?? CGSize(width: width, height: height)
                        if dragOrigin == nil { dragOrigin = origin }
                        width = PopoverSize.clampWidth(origin.width + value.translation.width)
                        height = PopoverSize.clampHeight(origin.height + value.translation.height)
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(Theme.Motion.smooth) {
                    width = PopoverSize.defaultWidth
                    height = PopoverSize.defaultHeight
                }
            }
            .tooltip("Drag to resize · double-click to reset")
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
                    .font(.ehHeadline)
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
                    HStack(spacing: Theme.Space.md) {
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
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: Theme.Size.navBar)
        .animation(Theme.Motion.page, value: route == nil)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .keyboardShortcut("[", modifiers: .command)
        .help("Back (⌘[)")
    }
}

private struct AppIdentity: View {
    var body: some View {
        HStack(spacing: 10) {
            AppIconMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("EmuHub")
                    .font(.ehTitle)
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
            RoundedRectangle(cornerRadius: Theme.Radius.md - 4, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Theme.Palette.accent.opacity(0.15),
                        Theme.Palette.secondaryAccent.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 30, height: 30)

            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Accent.brand)
        }
    }
}

private struct StatusPill: View {
    let running: Int

    private var isActive: Bool { running > 0 }

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(active: isActive)
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
                    isActive ? Theme.Palette.emulator.opacity(0.3) : Color.primary.opacity(0.06),
                    lineWidth: 1))
        )
        .animation(Theme.Motion.smooth, value: running)
    }
}

private struct NavMenuButton: View {
    @Binding var open: Bool

    var body: some View {
        IconButton(
            systemImage: open ? "xmark" : "line.3.horizontal",
            help: "Menu",
            size: Theme.Size.iconButton,
            symbolSize: 11,
            isActive: open
        ) {
            withAnimation(Theme.Motion.smooth) { open.toggle() }
        }
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
        .padding(.vertical, Theme.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.20), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
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
                    .foregroundStyle(destructive ? Theme.Palette.danger : .secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(destructive ? Theme.Palette.danger : .primary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.xl - 2)
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
