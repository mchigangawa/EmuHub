//
//  CommonComponents.swift
//  EmuHub
//

import SwiftUI

// MARK: - Banners

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

struct ActionBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green.opacity(0.9))
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.18), lineWidth: 1)
                )
        )
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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            if let label = actionLabel, let action = onAction {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.1),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )
        )
    }
}

