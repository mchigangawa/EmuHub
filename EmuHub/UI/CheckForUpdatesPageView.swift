//
//  CheckForUpdatesPageView.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 20/2/2026.
//

import SwiftUI

struct CheckForUpdatesPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                // MARK: Header
                UpdatePageHeader()

                // MARK: Update progress banner
                if state.isUpdating, let stage = state.updateStage {
                    UpdateProgressBanner(stage: stage)
                }

                // MARK: Error
                if let err = state.updateError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                            )
                    )
                }

                // MARK: Version card
                if let result = state.updateCheckResult {
                    UpdateResultCard(result: result, openURL: openURL)
                }

                // MARK: Primary action
                if let result = state.updateCheckResult, result.hasUpdate,
                   let downloadURL = result.downloadURL {
                    // Auto-update button
                    Button {
                        Task { await state.applyUpdate(downloadURL: downloadURL) }
                    } label: {
                        HStack(spacing: 8) {
                            if state.isUpdating {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(state.isUpdating
                                 ? (state.updateStage ?? "Updating…")
                                 : "Update Now")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isUpdating)

                    // Fallback: open in browser
                    Button {
                        openURL(downloadURL)
                    } label: {
                        Text("Download manually")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isUpdating)
                } else {
                    // Check now button
                    Button {
                        Task { await state.checkForUpdates() }
                    } label: {
                        HStack(spacing: 8) {
                            if state.isCheckingForUpdates {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(state.isCheckingForUpdates ? "Checking…" : "Check Now")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isCheckingForUpdates)
                }

                // MARK: Note
                Text("EmuHub replaces itself in-place and relaunches automatically. No data is sent from your device.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .task {
            if state.updateCheckResult == nil && !state.isCheckingForUpdates {
                await state.checkForUpdates()
            }
        }
    }
}

// MARK: - Progress Banner

private struct UpdateProgressBanner: View {
    let stage: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Installing Update")
                    .font(.system(size: 12, weight: .semibold))
                Text(stage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.18), lineWidth: 1)
                )
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Header

private struct UpdatePageHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.12), .cyan.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)

                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }

            VStack(spacing: 4) {
                Text("Software Update")
                    .font(.headline)

                Text("EmuHub can update itself automatically — no manual download required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(GlassCard(cornerRadius: 14))
    }
}

// MARK: - Update Result Card

private struct UpdateResultCard: View {
    let result: UpdateCheckResult
    let openURL: OpenURLAction

    var body: some View {
        VStack(spacing: 0) {
            VersionRow(
                icon: "checkmark.seal.fill",
                iconColor: .secondary,
                label: "Installed",
                value: result.currentVersion
            )

            Divider().padding(.leading, 44)

            VersionRow(
                icon: "tag.fill",
                iconColor: result.hasUpdate ? .orange : .green,
                label: "Latest",
                value: result.latestVersion
            )

            Divider().padding(.leading, 44)

            HStack(spacing: 12) {
                Image(systemName: result.hasUpdate ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(result.hasUpdate ? .orange : .green)
                    .frame(width: 24)

                Text(result.hasUpdate ? "A new version is available" : "You're up to date")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(result.hasUpdate ? .orange : .green)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(GlassCard(cornerRadius: 12))

        // Release notes link (always available)
        Button {
            openURL(result.releaseNotesURL)
        } label: {
            Label("View Release Notes", systemImage: "doc.text")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

private struct VersionRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
