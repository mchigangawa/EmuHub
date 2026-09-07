//
//  Controls.swift
//  EmuHub
//
//  The app's shared control vocabulary. Every search field, round icon button,
//  hover-expanding pill, section header, and panel chrome in EmuHub is one of
//  these — previously each screen grew its own near-identical copy, which made
//  density and hover behaviour drift between pages.
//

import SwiftUI

// MARK: - Search Field

/// The single search/filter input used on Home, App Manager, and Logcat.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    /// Capsule reads better inside dense toolbars; rounded rect inside page content.
    var shape: Shape = .roundedRect
    /// Focus the field as soon as it appears (used when revealed by a toggle).
    var autoFocus: Bool = false
    /// Called when the user clears an already-empty field — lets the caller
    /// collapse a reveal-on-demand search affordance.
    var onDismiss: (() -> Void)? = nil

    @FocusState private var focused: Bool

    enum Shape { case capsule, roundedRect }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)

            if !text.isEmpty || onDismiss != nil {
                Button {
                    if text.isEmpty { onDismiss?() } else { text = "" }
                } label: {
                    Image(systemName: text.isEmpty ? "xmark" : "xmark.circle.fill")
                        .font(.system(size: text.isEmpty ? 10 : 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(text.isEmpty ? "Close search" : "Clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            let border = focused ? Theme.Palette.accent.opacity(0.55)
                                 : Color.primary.opacity(0.08)
            switch shape {
            case .capsule:
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            case .roundedRect:
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(border, lineWidth: 1)
                    )
            }
        }
        .animation(Theme.Motion.fade, value: focused)
        .onAppear { if autoFocus { focused = true } }
    }
}

// MARK: - Tooltip

/// A fast, in-app tooltip naming what an icon-only control does.
///
/// macOS's built-in `.help(_:)` tooltip takes well over a second to appear and
/// renders in the system's own style, which made EmuHub's icon-only buttons hard
/// to learn. This names the feature shortly after hover, in the app's own visual
/// language. `.help(_:)` is still applied alongside it as the accessibility and
/// long-hover fallback.
///
/// The label is drawn by `tooltipLayer()` at the root of the popover rather than
/// as an overlay on the control itself, because many controls sit inside clipped
/// containers (`GlassGroup`, scroll views) that would cut an in-place label off.
/// The control only publishes *where* its label should go; the root decides how
/// to fit it on screen.
struct TooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            )
    }
}

/// A control's request to have its name drawn, and the rectangle to anchor to.
struct TooltipItem {
    let text: String
    let anchor: Anchor<CGRect>
}

struct TooltipPreferenceKey: PreferenceKey {
    static let defaultValue: [TooltipItem] = []

    static func reduce(value: inout [TooltipItem], nextValue: () -> [TooltipItem]) {
        value.append(contentsOf: nextValue())
    }
}

/// Delay before a tooltip appears — long enough that sweeping the pointer across
/// a toolbar doesn't flash every label, short enough to feel responsive.
private let tooltipDelay: Duration = .milliseconds(320)

private struct TooltipModifier: ViewModifier {
    let text: String

    @State private var hovered = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hovered = hovering
                if !hovering { visible = false }
            }
            .task(id: hovered) {
                guard hovered, !text.isEmpty else { return }
                try? await Task.sleep(for: tooltipDelay)
                guard hovered else { return }
                visible = true
            }
            .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) { anchor in
                visible && !text.isEmpty ? [TooltipItem(text: text, anchor: anchor)] : []
            }
    }
}

extension View {
    /// Names this control on hover, and registers the same text as the system
    /// tooltip for accessibility. Requires a `tooltipLayer()` above it.
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
            .modifier(HelpIfPresent(help: text))
    }

    /// Draws hover labels for every `tooltip(_:)` beneath this view, positioned
    /// so they stay inside its bounds. Apply once, at the root of a window.
    func tooltipLayer() -> some View {
        overlayPreferenceValue(TooltipPreferenceKey.self) { items in
            GeometryReader { proxy in
                if let item = items.last {
                    TooltipPresenter(item: item, container: proxy)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Places one tooltip beside its control, flipping above when there's no room
/// below and clamping horizontally so it never runs off the popover's edge.
private struct TooltipPresenter: View {
    let item: TooltipItem
    let container: GeometryProxy

    @State private var labelSize: CGSize = .zero

    /// Gap between the control and its label.
    private let gap: CGFloat = 8
    /// Keep-out margin from the container's edges.
    private let margin: CGFloat = 6

    var body: some View {
        let target = container[item.anchor]
        let bounds = container.size

        let fitsBelow = target.maxY + gap + labelSize.height + margin <= bounds.height
        let y = fitsBelow
            ? target.maxY + gap + labelSize.height / 2
            : target.minY - gap - labelSize.height / 2

        let halfWidth = labelSize.width / 2
        let x = min(max(target.midX, halfWidth + margin), bounds.width - halfWidth - margin)

        TooltipLabel(text: item.text)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TooltipSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(TooltipSizeKey.self) { labelSize = $0 }
            // Hidden until measured, so the first frame doesn't flash in the
            // wrong place before the label's size is known.
            .opacity(labelSize == .zero ? 0 : 1)
            .position(x: x, y: y)
            .animation(Theme.Motion.fade, value: item.text)
    }
}

private struct TooltipSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Icon Button

/// A round icon button with a consistent hover treatment. Replaces the several
/// bespoke circular buttons that used to live in each view.
struct IconButton: View {
    let systemImage: String
    var help: String = ""
    var style: Style = .plain
    var size: CGFloat = Theme.Size.iconButton
    var symbolSize: CGFloat = 12
    /// Keeps the button visually "on" independent of hover (e.g. an active filter).
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovered = false

    enum Style {
        /// Neutral grey wash that appears on hover.
        case plain
        /// Tinted glass chip — always faintly visible, brighter on hover.
        case tinted(Color)
        /// Filled accent gradient for the primary action in a group.
        case prominent(Color)
        /// Destructive tint.
        case danger
    }

    private var isOn: Bool { hovered || isActive }

    var body: some View {
        Button(action: action) {
            ZStack {
                background
                Image(systemName: systemImage)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(foreground)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.snappy, value: hovered)
        .tooltip(help)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .plain:
            Circle().fill(Color.primary.opacity(isOn ? 0.10 : 0.05))
        case .tinted(let tint):
            Circle().fill(.ultraThinMaterial)
                .overlay(Circle().fill(tint.opacity(isOn ? 0.18 : 0.06)))
                .overlay(Circle().strokeBorder(tint.opacity(isOn ? 0.40 : 0.14), lineWidth: 0.75))
        case .prominent(let tint):
            Circle().fill(Accent.gradient(tint))
                .shadow(color: tint.opacity(hovered ? 0.5 : 0.3), radius: hovered ? 5 : 3, y: 1)
        case .danger:
            Circle().fill(Theme.Palette.danger.opacity(isOn ? 0.16 : 0.08))
        }
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .plain:
            return AnyShapeStyle(isOn ? Color.primary : Color.secondary)
        case .tinted(let tint):
            return AnyShapeStyle(isOn ? tint : tint.opacity(0.75))
        case .prominent:
            return AnyShapeStyle(Color.white)
        case .danger:
            return AnyShapeStyle(Theme.Palette.danger)
        }
    }
}

/// `.help("")` still installs an empty tooltip, so only attach it when there's text.
private struct HelpIfPresent: ViewModifier {
    let help: String
    func body(content: Content) -> some View {
        if help.isEmpty { content } else { content.help(help) }
    }
}

// MARK: - Expanding Pill Button

/// A compact capsule that shows only its icon until `expanded`, then slides a
/// label out beside it. Used for Launch / Stop and other per-row primary actions.
struct ExpandingPill: View {
    let systemImage: String
    let label: String
    var tint: Color = Theme.Palette.accent
    var style: Style = .filled
    /// Driven by the parent row's hover state so the whole card reveals together.
    var expanded: Bool
    let action: () -> Void

    enum Style {
        /// Solid tinted capsule with white content — a primary action.
        case filled
        /// Frosted capsule with tinted content — a secondary action.
        case glass
        /// Muted until expanded, then turns the tint colour — for destructive
        /// actions that shouldn't shout while idle.
        case quiet
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                if expanded {
                    Text(label)
                        .font(.ehCaptionEmphasis)
                        .lineLimit(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .fixedSize()
            .foregroundStyle(foreground)
            .padding(.horizontal, expanded ? 11 : 8)
            .padding(.vertical, 7)
            .background(background)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(Theme.Motion.snappy, value: expanded)
        // The pill already slides its own label out on hover, so it needs no
        // tooltip — only the system fallback for accessibility.
        .help(label)
    }

    private var foreground: Color {
        switch style {
        case .filled, .quiet: .white
        case .glass: tint
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .filled:
            Capsule()
                .fill(expanded ? tint : tint.opacity(0.7))
                .shadow(color: expanded ? tint.opacity(0.3) : .clear, radius: 4, y: 2)
        case .glass:
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        case .quiet:
            Capsule().fill(expanded ? tint : Color.secondary.opacity(0.4))
        }
    }
}

// MARK: - Section Header

/// The uppercase label + count + trailing actions that opens each Home section.
struct SectionHeader: View {
    let icon: String
    let title: String
    var color: Color = Theme.Palette.accent
    var count: Int = 0
    var actions: [SectionAction] = []

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text(title.uppercased())
                .font(.ehSectionLabel)
                .foregroundStyle(.secondary)
                .kerning(0.5)

            if count > 0 {
                CountBadge(count: count, tint: color)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: Theme.Space.sm)

            if !actions.isEmpty {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(actions) { action in
                        IconButton(
                            systemImage: action.icon,
                            help: action.help,
                            style: action.prominent ? .prominent(color) : .tinted(color),
                            size: 24,
                            symbolSize: 11,
                            isActive: action.active,
                            action: action.perform
                        )
                    }
                }
            }
        }
        .animation(Theme.Motion.smooth, value: count)
    }
}

struct SectionAction: Identifiable {
    let id: String
    let icon: String
    var help: String = ""
    var active: Bool = false
    /// Renders as a filled accent action — reserve for the one primary "add".
    var prominent: Bool = false
    let perform: () -> Void
}

/// A frosted pill showing a section's item count, tinted to the section colour.
struct CountBadge: View {
    let count: Int
    var tint: Color = Theme.Palette.accent

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .monospacedDigit()
            .frame(minWidth: 11)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xxs)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.75))
            )
            .contentTransition(.numericText())
    }
}

// MARK: - Status Dot

/// A small filled dot with an optional glow, used for live/idle indicators.
struct StatusDot: View {
    var color: Color = Theme.Palette.emulator
    var active: Bool = true
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(active ? color : Color.secondary.opacity(0.3))
            .frame(width: size, height: size)
            .shadow(color: active ? color.opacity(0.45) : .clear, radius: 3)
    }
}

// MARK: - Panel Chrome

/// The header shared by every full-bleed overlay panel (App Manager, Logcat,
/// Device Inspector): tinted glyph tile, title, device subtitle, close button.
struct PanelHeader<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.lg) {
            GlassIconTile(systemImage: icon, color: tint, size: Theme.Size.avatarSmall)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ehHeadline)
                if let subtitle {
                    Text(subtitle)
                        .font(.ehFootnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Theme.Space.md)

            trailing()

            IconButton(systemImage: "xmark", help: "Close", size: 24, symbolSize: 11, action: onClose)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.lg)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(icon: String, tint: Color, title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle,
                  onClose: onClose, trailing: { EmptyView() })
    }
}

/// The opaque-then-frosted backdrop used by overlay panels, so content behind
/// them can't bleed through while they still read as glass.
struct PanelBackground: View {
    var tint: Color = Theme.Palette.accent

    var body: some View {
        ZStack {
            Rectangle().fill(Color(NSColor.windowBackgroundColor))
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
            LinearGradient(
                colors: [tint.opacity(0.05), .clear, Theme.Palette.secondaryAccent.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

/// Centred icon + message used for a panel's loading / empty / error state.
struct PanelMessage: View {
    var systemImage: String? = nil
    var showsProgress: Bool = false
    let message: String
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            if showsProgress {
                ProgressView()
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(tint)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }
}
