//
//  CommonComponents.swift
//  EmuHub
//

import SwiftUI

// MARK: - Notice Banner

/// The inline banner used for transient success and error feedback. Both used to
/// be separate near-identical views; the only real difference is the role, so
/// that's the only thing callers pick.
struct NoticeBanner: View {
    enum Role {
        case success, warning, failure

        var tint: Color {
            switch self {
            case .success: Theme.Palette.emulator
            case .warning: Theme.Palette.warning
            case .failure: Theme.Palette.danger
            }
        }

        var systemImage: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.circle.fill"
            case .failure: "exclamationmark.triangle.fill"
            }
        }
    }

    let role: Role
    let message: String
    /// When provided, the banner gains a dismiss button — errors persist until
    /// something clears them, so they need a way out that isn't "wait".
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: role.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(role.tint)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(role.tint.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: Theme.Space.xs)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(role.tint.opacity(0.7))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xs + 4, style: .continuous)
                .fill(role.tint.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xs + 4, style: .continuous)
                        .strokeBorder(role.tint.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

/// Convenience wrappers so call sites read as intent rather than configuration.
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        NoticeBanner(role: .failure, message: message, onDismiss: onDismiss)
    }
}

struct ActionBanner: View {
    let message: String

    var body: some View {
        NoticeBanner(role: .success, message: message)
    }
}

// MARK: - Empty State

struct EmptyStateCard: View {
    let icon: String
    let message: String
    var detail: String? = nil
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.ehBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let detail {
                Text(detail)
                    .font(.ehCaption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.xxl)
            }

            if let label = actionLabel, let action = onAction {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xs + 4, style: .continuous)
                .fill(Color.secondary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xs + 4, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.1),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
        )
    }
}
