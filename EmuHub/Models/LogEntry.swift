//
//  LogEntry.swift
//  EmuHub
//
//  A single parsed line of `adb logcat -v threadtime` output.
//

import SwiftUI

/// Android log priority levels, ordered by severity (verbose → fatal).
nonisolated enum LogLevel: String, CaseIterable, Sendable {
    case verbose = "V"
    case debug   = "D"
    case info    = "I"
    case warning = "W"
    case error   = "E"
    case fatal   = "F"

    /// Severity rank used for "minimum level" filtering (verbose lowest, fatal highest).
    var priority: Int {
        switch self {
        case .verbose: 0
        case .debug:   1
        case .info:    2
        case .warning: 3
        case .error:   4
        case .fatal:   5
        }
    }

    var label: String {
        switch self {
        case .verbose: "Verbose"
        case .debug:   "Debug"
        case .info:    "Info"
        case .warning: "Warn"
        case .error:   "Error"
        case .fatal:   "Fatal"
        }
    }

    var color: Color {
        switch self {
        case .verbose: .secondary
        case .debug:   .blue
        case .info:    .green
        case .warning: .orange
        case .error:   .red
        case .fatal:   .pink
        }
    }

    init(token: Substring) {
        self = LogLevel(rawValue: String(token.prefix(1)).uppercased()) ?? .info
    }
}

/// One logcat line. `id` is a monotonic sequence number assigned at ingest so
/// SwiftUI can diff a high-churn list cheaply without hashing the whole struct.
nonisolated struct LogEntry: Identifiable, Sendable {
    let id: Int
    let timestamp: String
    let pid: String
    let tag: String
    let level: LogLevel
    let message: String

    /// Parses a single `-v threadtime` line:
    /// `MM-DD HH:MM:SS.mmm  PID  TID L TAG: message`
    ///
    /// Non-standard lines (e.g. `--------- beginning of main`) are kept verbatim
    /// as a verbose entry so nothing is silently dropped. Returns the parsed entry
    /// stamped with `id`.
    static func parse(_ raw: String, id: Int) -> LogEntry {
        if raw.hasPrefix("---------") {
            return LogEntry(id: id, timestamp: "", pid: "", tag: "—",
                            level: .verbose,
                            message: raw.trimmingCharacters(in: .whitespaces))
        }

        var rest = Substring(raw)
        func nextToken() -> Substring? {
            while rest.first == " " { rest = rest.dropFirst() }
            guard !rest.isEmpty else { return nil }
            guard let space = rest.firstIndex(of: " ") else {
                defer { rest = rest[rest.endIndex...] }
                return rest
            }
            let token = rest[..<space]
            rest = rest[space...]
            return token
        }

        guard let date = nextToken(),
              let time = nextToken(),
              let pid = nextToken(),
              let _ = nextToken(),                 // tid — captured for format, not displayed
              let levelToken = nextToken() else {
            return LogEntry(id: id, timestamp: "", pid: "", tag: "",
                            level: .info, message: raw)
        }

        while rest.first == " " { rest = rest.dropFirst() }

        // Remainder is "TAG: message"; split on the first ": ".
        let tag: String
        let message: String
        if let colon = rest.range(of: ": ") {
            tag = String(rest[..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
            message = String(rest[colon.upperBound...])
        } else {
            tag = ""
            message = String(rest)
        }

        return LogEntry(
            id: id,
            timestamp: "\(date) \(time)",
            pid: String(pid),
            tag: tag,
            level: LogLevel(token: levelToken),
            message: message
        )
    }
}
