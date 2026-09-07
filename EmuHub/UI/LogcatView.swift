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
    @State private var showTimestamps = false
    /// Auto-scroll sticks to the newest line, and is suspended while paused so a
    /// log you paused to read doesn't jump away when the buffer updates.
    @State private var autoScroll = true

    private var filtered: [LogEntry] {
        state.logEntries.filter { entry in
            guard entry.level.priority >= minLevel.priority else { return false }
            guard !search.isEmpty else { return true }
            return entry.tag.localizedCaseInsensitiveContains(search)
                || entry.message.localizedCaseInsensitiveContains(search)
                || entry.pid == search
        }
    }

    /// Plain-text rendering of the currently visible (filtered) lines.
    private func renderedText() -> String {
        filtered.map { entry in
            let head = entry.timestamp.isEmpty ? "" : "\(entry.timestamp) "
            let tag = entry.tag.isEmpty ? "" : "\(entry.tag): "
            return "\(head)\(entry.level.rawValue)/\(tag)\(entry.message)"
        }
        .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                icon: "doc.text.magnifyingglass",
                tint: Theme.Palette.emulator,
                title: "Logcat",
                subtitle: device.displayName,
                onClose: { state.closeLogcat() }
            ) {
                if !state.logEntries.isEmpty {
                    Text("\(filtered.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("\(filtered.count) of \(state.logEntries.count) lines shown")
                }
            }

            Hairline(inset: 0).opacity(0.5)

            toolbar

            if let error = state.logcatError {
                NoticeBanner(role: .warning, message: error)
                    .pageGutter()
                    .padding(.top, Theme.Space.md)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground(tint: Theme.Palette.emulator) }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Space.md) {
            LevelFilterMenu(minLevel: $minLevel)

            SearchField(text: $search, placeholder: "Filter tag, message, or PID…", shape: .capsule)

            IconButton(
                systemImage: state.isLogcatPaused ? "play.fill" : "pause.fill",
                help: state.isLogcatPaused ? "Resume" : "Pause",
                style: state.isLogcatPaused ? .tinted(Theme.Palette.emulator) : .plain,
                size: Theme.Size.iconButtonSmall,
                isActive: state.isLogcatPaused
            ) { state.toggleLogcatPause() }

            IconButton(
                systemImage: "clock",
                help: showTimestamps ? "Hide timestamps" : "Show timestamps",
                size: Theme.Size.iconButtonSmall,
                isActive: showTimestamps
            ) {
                withAnimation(Theme.Motion.fade) { showTimestamps.toggle() }
            }

            IconButton(systemImage: "trash", help: "Clear", size: Theme.Size.iconButtonSmall) {
                state.clearLogcat()
            }

            ExportMenu(disabled: filtered.isEmpty, text: renderedText)
                .environmentObject(state)
        }
        .pageGutter()
        .padding(.top, Theme.Space.md)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            if state.logEntries.isEmpty && state.logcatError == nil {
                PanelMessage(showsProgress: true, message: "Waiting for logs…")
            } else {
                PanelMessage(
                    systemImage: "line.3.horizontal.decrease.circle",
                    message: state.logEntries.isEmpty
                        ? "No log output"
                        : "No lines match the current filter"
                )
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { entry in
                            LogcatRow(entry: entry, showTimestamp: showTimestamps)
                                .id(entry.id)
                        }
                        // Anchor for auto-scroll-to-bottom.
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
                }
                .onChange(of: state.logEntries.count) {
                    guard autoScroll, !state.isLogcatPaused else { return }
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
                .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private let bottomAnchor = "logcat-bottom"
}

// MARK: - Toolbar Pieces

private struct LevelFilterMenu: View {
    @Binding var minLevel: LogLevel

    var body: some View {
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
            .padding(.vertical, Theme.Space.sm)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tooltip("Show this level and above")
    }
}

private struct ExportMenu: View {
    @EnvironmentObject var state: AppState
    let disabled: Bool
    let text: () -> String

    var body: some View {
        Menu {
            Button { state.copyLog(text()) } label: {
                Label("Copy Visible Logs", systemImage: "doc.on.doc")
            }
            Button { state.saveLog(text()) } label: {
                Label("Save to Desktop", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.iconButtonSmall, height: Theme.Size.iconButtonSmall)
                .background(Circle().fill(Color.primary.opacity(0.05)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(disabled)
        .tooltip("Export logs")
    }
}

// MARK: - Log Row

private struct LogcatRow: View {
    let entry: LogEntry
    var showTimestamp: Bool = false

    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Text(entry.level.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.xs - 2, style: .continuous)
                        .fill(entry.level.color)
                )

            VStack(alignment: .leading, spacing: 1) {
                if showTimestamp || (!entry.tag.isEmpty && entry.tag != "—") {
                    HStack(spacing: Theme.Space.sm) {
                        if showTimestamp && !entry.timestamp.isEmpty {
                            Text(entry.timestamp)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        if !entry.tag.isEmpty && entry.tag != "—" {
                            Text(entry.tag)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(entry.level.color.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                }

                Text(entry.message)
                    .font(.ehMonoSmall)
                    .foregroundStyle(entry.level == .verbose ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, Theme.Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xs - 2, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.04 : 0))
        )
        .onHover { hovered = $0 }
    }
}
