//
//  LogcatView.swift
//  EmuHub
//

import SwiftUI

// MARK: - Logcat Viewer (in-popover panel)

struct LogcatView: View {
    @EnvironmentObject var state: AppState
    let device: RunningDevice

    @State private var search = ""
    @State private var minLevel: LogLevel = .verbose
    @State private var autoScroll = true

    private var filtered: [LogEntry] {
        state.logEntries.filter { entry in
            guard entry.level.priority >= minLevel.priority else { return false }
            guard !search.isEmpty else { return true }
            return entry.tag.localizedCaseInsensitiveContains(search)
                || entry.message.localizedCaseInsensitiveContains(search)
        }
    }

    /// Plain-text rendering of the currently visible (filtered) lines.
    private func renderedText() -> String {
        filtered.map { e in
            let head = e.timestamp.isEmpty ? "" : "\(e.timestamp) "
            let tag = e.tag.isEmpty ? "" : "\(e.tag): "
            return "\(head)\(e.level.rawValue)/\(tag)\(e.message)"
        }
        .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            toolbar
            if let err = state.logcatError {
                LogcatNotice(message: err)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(Color(NSColor.windowBackgroundColor))
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [Color.green.opacity(0.05), .clear, Color.blue.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            GlassIconTile(systemImage: "doc.text.magnifyingglass", color: .green, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Logcat")
                    .font(.system(size: 13, weight: .semibold))
                Text(device.displayName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { state.closeLogcat() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Minimum level filter
            Menu {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Button {
                        minLevel = level
                    } label: {
                        if minLevel == level {
                            Label(level.label, systemImage: "checkmark")
                        } else {
                            Text(level.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(minLevel.color).frame(width: 7, height: 7)
                    Text(minLevel.label)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Show this level and above")

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Filter tag or message…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

            LogcatIconButton(
                icon: state.isLogcatPaused ? "play.fill" : "pause.fill",
                tint: state.isLogcatPaused ? .green : .secondary,
                help: state.isLogcatPaused ? "Resume" : "Pause"
            ) { state.toggleLogcatPause() }

            LogcatIconButton(icon: "trash", tint: .secondary, help: "Clear") {
                state.clearLogcat()
            }

            Menu {
                Button {
                    state.copyLog(renderedText())
                } label: {
                    Label("Copy Visible Logs", systemImage: "doc.on.doc")
                }
                Button {
                    state.saveLog(renderedText())
                } label: {
                    Label("Save to Desktop", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.1)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(filtered.isEmpty)
            .help("Export logs")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    // MARK: Content

    private var content: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    if state.logEntries.isEmpty && state.logcatError == nil {
                        ProgressView()
                        Text("Waiting for logs…")
                    } else {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 22)).foregroundStyle(.tertiary)
                        Text(state.logEntries.isEmpty ? "No log output" : "No lines match the current filter")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(filtered) { entry in
                                LogcatRow(entry: entry)
                                    .id(entry.id)
                            }
                            // Anchor for auto-scroll-to-bottom.
                            Color.clear.frame(height: 1).id(bottomAnchor)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: state.logEntries.count) {
                        guard autoScroll, !state.isLogcatPaused else { return }
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                    .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private let bottomAnchor = "logcat-bottom"
}

private struct LogcatRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(entry.level.color))

            VStack(alignment: .leading, spacing: 1) {
                if !entry.tag.isEmpty && entry.tag != "—" {
                    Text(entry.tag)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(entry.level.color.opacity(0.9))
                        .lineLimit(1)
                }
                Text(entry.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(entry.level == .verbose ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct LogcatIconButton: View {
    let icon: String
    var tint: Color = .secondary
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? tint.opacity(1) : tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.secondary.opacity(hovered ? 0.16 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

private struct LogcatNotice: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

