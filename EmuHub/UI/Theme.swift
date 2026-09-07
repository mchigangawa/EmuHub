//
//  Theme.swift
//  EmuHub
//
//  The single source of truth for spacing, radii, typography, motion, and
//  semantic colour. Every view should reach for a token here rather than
//  hard-coding a number, so density and rhythm stay consistent as the app grows.
//

import SwiftUI

// MARK: - Theme Tokens

enum Theme {

    // MARK: Spacing

    /// A 4-point spacing scale. `gutter` is the standard horizontal page inset.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24

        /// Horizontal inset used by every scrollable page and toolbar.
        static let gutter: CGFloat = 14
        /// Vertical gap between sibling cards in a list.
        static let rowGap: CGFloat = 6
    }

    // MARK: Radii

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 9
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    // MARK: Sizes

    enum Size {
        /// Height of the app's top navigation bar.
        static let navBar: CGFloat = 54
        /// Square edge of the round icon buttons used in toolbars and cards.
        static let iconButton: CGFloat = 28
        /// Smaller icon button, used inside dense toolbars.
        static let iconButtonSmall: CGFloat = 26
        /// Device / AVD avatar tile.
        static let avatar: CGFloat = 36
        /// Avatar used in panel headers and settings rows.
        static let avatarSmall: CGFloat = 30
    }

    // MARK: Motion

    /// Named animations so timing reads consistently across the app instead of
    /// each view inventing its own spring.
    enum Motion {
        /// Quick feedback: hover, toggles, button state.
        static let snappy = Animation.spring(response: 0.22, dampingFraction: 0.78)
        /// Standard UI transitions: reveal, expand, list changes.
        static let smooth = Animation.spring(response: 0.30, dampingFraction: 0.82)
        /// Larger movements: page pushes, panel presentation.
        static let page = Animation.spring(response: 0.38, dampingFraction: 0.86)
        /// Non-spring fade for banners and opacity-only changes.
        static let fade = Animation.easeOut(duration: 0.18)
    }

    // MARK: Semantic Colour

    /// Roles rather than raw colours, so a device's accent is decided in one
    /// place and every surface that tints itself agrees.
    enum Palette {
        static let emulator = Color.green
        static let physical = Color.blue
        static let warning = Color.orange
        static let danger = Color.red
        static let neutral = Color.secondary
        static let accent = Color.blue
        static let secondaryAccent = Color.purple
    }

    // MARK: Hairlines

    /// Opacity used for the app's divider hairlines. Kept very low so the glass
    /// reads as one continuous surface rather than stacked boxes.
    static let hairline: Double = 0.07
}

// MARK: - Typography

extension Font {
    /// App name / prominent headers.
    static let ehTitle = Font.system(size: 14, weight: .semibold, design: .rounded)
    /// Page and panel titles in the nav bar.
    static let ehHeadline = Font.system(size: 13, weight: .semibold)
    /// Primary row text (device names, setting titles).
    static let ehBody = Font.system(size: 13, weight: .medium)
    /// Secondary row text (status lines, descriptions).
    static let ehCaption = Font.system(size: 11)
    /// Emphasised secondary text (button labels, badges).
    static let ehCaptionEmphasis = Font.system(size: 11, weight: .semibold)
    /// Smallest supporting text (timestamps, hints).
    static let ehFootnote = Font.system(size: 10.5)
    /// Uppercase section labels.
    static let ehSectionLabel = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    /// Monospaced content: package names, paths, log messages.
    static let ehMono = Font.system(size: 12, design: .monospaced)
    static let ehMonoSmall = Font.system(size: 11, design: .monospaced)
}

// MARK: - Shared View Helpers

extension View {
    /// The standard horizontal page inset.
    func pageGutter() -> some View {
        padding(.horizontal, Theme.Space.gutter)
    }

    /// A near-invisible full-width separator matching the app's hairline weight.
    func hairlineDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(Theme.hairline))
                .frame(height: 1)
        }
    }
}

/// A hairline rule used between stacked sections.
struct Hairline: View {
    var inset: CGFloat = Theme.Space.gutter

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(Theme.hairline))
            .frame(height: 1)
            .padding(.horizontal, inset)
    }
}
