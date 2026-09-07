//
//  DesignSystem.swift
//  EmuHub
//
//  Shared glassy/translucent design primitives: vibrancy backgrounds, frosted
//  cards, and reusable surfaces used across the menu-bar UI.
//

import SwiftUI
import AppKit

// MARK: - Vibrancy Background

/// An `NSVisualEffectView`-backed background that lets the desktop / windows
/// behind the popover blur through, giving the panel a true translucent feel.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
    }
}

// MARK: - Glass Card

/// A frosted-glass surface for rows and panels. Layers an ultra-thin material
/// with a soft inner highlight on top and a hairline stroke for definition.
struct GlassCard: View {
    var cornerRadius: CGFloat = 12
    /// Optional accent tint that bleeds subtly into the glass.
    var tint: Color? = nil
    /// Raises the card with a stronger highlight + shadow when hovered/active.
    var elevated: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                if let tint {
                    shape.fill(
                        LinearGradient(
                            colors: [tint.opacity(elevated ? 0.16 : 0.10), tint.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                // Top-edge sheen that sells the "glass" look.
                shape.stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(elevated ? 0.30 : 0.18),
                            .white.opacity(0.04),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(elevated ? 0.18 : 0.08),
                    radius: elevated ? 10 : 4, y: elevated ? 4 : 2)
    }
}

// MARK: - Glass Group

/// A frosted container for grouped rows (settings sections, link lists, FAQ
/// accordions). Clips its content to the rounded shape so full-bleed row hover
/// highlights stay inside the corners, then lays a `GlassCard` behind — letting
/// the popover's vibrancy show through instead of a flat opaque fill.
struct GlassGroup<Content: View>: View {
    var cornerRadius: CGFloat = 12
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(GlassCard(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - Glass Field

/// Frosted background for plain text fields so inputs read as glass rather than
/// the default opaque bezel.
private struct GlassFieldBackground: ViewModifier {
    var cornerRadius: CGFloat = 9
    var focused: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                focused ? Color.blue.opacity(0.55) : Color.primary.opacity(0.10),
                                lineWidth: 1
                            )
                    )
            )
    }
}

extension View {
    /// Wraps a `.plain` text field (or similar) in a frosted-glass field surface.
    func glassField(cornerRadius: CGFloat = 9, focused: Bool = false) -> some View {
        modifier(GlassFieldBackground(cornerRadius: cornerRadius, focused: focused))
    }
}

// MARK: - Accent Gradients

enum Accent {
    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let brand = LinearGradient(
        colors: [.blue, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Glass Icon Chip

/// A rounded, tinted glass tile holding an SF Symbol — used for device avatars.
struct GlassIconTile: View {
    let systemImage: String
    var color: Color = .blue
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Accent.gradient(color).opacity(0.22))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(color.opacity(0.30), lineWidth: 0.75)
            }
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Accent.gradient(color))
            }
    }
}
