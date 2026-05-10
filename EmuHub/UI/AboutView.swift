//
//  AboutView.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 20/2/2026.
//

import SwiftUI

struct AboutPage: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // MARK: Hero
                ZStack {
                    LinearGradient(
                        colors: [.blue.opacity(0.09), .purple.opacity(0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [.blue.opacity(0.22), .purple.opacity(0.22)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 64, height: 64)
                                .shadow(color: .blue.opacity(0.18), radius: 12, y: 4)

                            Image(systemName: "iphone.and.arrow.forward")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        }

                        VStack(spacing: 4) {
                            Text("EmuHub")
                                .font(.system(size: 20, weight: .bold, design: .rounded))

                            Text("Android Device Manager for macOS")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                VersionBadge(label: "v\(appVersion)")
                                Text("·").foregroundStyle(.quaternary)
                                VersionBadge(label: "Build \(buildNumber)")
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 28)
                }

                Divider()

                // MARK: What EmuHub does
                VStack(alignment: .leading, spacing: 12) {
                    AboutSectionLabel("Overview")

                    Text("A lightweight menu bar utility for managing Android Virtual Devices and connected physical Android devices — with zero Terminal required. Click the icon, launch an AVD, and you're done.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                Divider()

                // MARK: Feature highlights
                VStack(alignment: .leading, spacing: 10) {
                    AboutSectionLabel("Features")

                    let features: [(String, Color, String)] = [
                        ("square.stack.3d.up.fill", .blue, "List, launch, cold-boot, and wipe AVDs"),
                        ("plus.circle.fill", .indigo, "Create new AVDs without Android Studio"),
                        ("iphone", .blue, "Physical device visibility with model resolution"),
                        ("camera.fill", .purple, "Screenshot capture saved to Desktop"),
                        ("arrow.down.app.fill", .orange, "APK drag-and-drop install"),
                        ("bolt.circle.fill", .green, "Auto-refresh with configurable interval"),
                        ("arrow.trianglehead.2.clockwise.rotate.90.circle", .teal, "In-app update checker via GitHub Releases"),
                    ]

                    VStack(spacing: 6) {
                        ForEach(features, id: \.2) { icon, color, label in
                            FeatureRow(icon: icon, color: color, label: label)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                Divider()

                // MARK: Details
                VStack(spacing: 0) {
                    AboutInfoRow(label: "Developer", value: "Munyaradzi Chigangawa")
                    Divider().padding(.leading, 18)
                    AboutInfoRow(label: "License", value: "MIT Open Source")
                    Divider().padding(.leading, 18)
                    AboutInfoRow(label: "Requires", value: "macOS 13 Ventura or later")
                    Divider().padding(.leading, 18)
                    AboutInfoRow(label: "Built with", value: "Swift · SwiftUI")
                }

                Divider()

                // MARK: Links
                VStack(spacing: 0) {
                    AboutLinkRow(icon: "star.fill", color: .yellow,
                                 label: "GitHub Repository",
                                 url: "https://github.com/mchigangawa/EmuHub")
                    Divider().padding(.leading, 46)
                    AboutLinkRow(icon: "doc.text.fill", color: .blue,
                                 label: "Changelog",
                                 url: "https://github.com/mchigangawa/EmuHub/blob/main/CHANGELOG.md")
                    Divider().padding(.leading, 46)
                    AboutLinkRow(icon: "exclamationmark.bubble.fill", color: .red,
                                 label: "Report an Issue",
                                 url: "https://github.com/mchigangawa/EmuHub/issues")
                    Divider().padding(.leading, 46)
                    AboutLinkRow(icon: "person.2.fill", color: .purple,
                                 label: "Contributing Guide",
                                 url: "https://github.com/mchigangawa/EmuHub/blob/main/CONTRIBUTING.md")
                    Divider().padding(.leading, 46)
                    AboutLinkRow(icon: "hand.raised.fill", color: .green,
                                 label: "MIT License",
                                 url: "https://github.com/mchigangawa/EmuHub/blob/main/LICENSE")
                }

                Divider()

                // MARK: Footer
                Text("© 2026 Munyaradzi Chigangawa · MIT License")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.vertical, 14)
            }
        }
    }
}

// MARK: - Components

private struct VersionBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1))
            )
    }
}

private struct AboutSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .kerning(0.5)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.1))
                    .frame(width: 24, height: 24)
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

private struct AboutInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct AboutLinkRow: View {
    let icon: String
    let color: Color
    let label: String
    let url: String
    @State private var hovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.1))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(hovered ? Color.primary.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
