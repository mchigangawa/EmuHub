//
//  LogcatService.swift
//  EmuHub
//
//  Streams `adb logcat` from a device and delivers parsed entries in batches.
//

import Foundation

/// Owns a live `adb logcat` process and turns its stdout into batches of
/// `LogEntry`. Unlike `Shell.run` (one-shot, buffered), this reads incrementally
/// so output appears as it is produced.
///
/// Not `@MainActor`: the reader runs on the file handle's background queue and
/// parsing happens there to keep the main thread free. Callbacks are `@Sendable`;
/// the caller hops to the main actor to publish results.
nonisolated final class LogcatService {
    /// Per-stream parsing state mutated only from the file handle's serialized
    /// readability queue, hence safe to share unchecked across that one boundary.
    private final class StreamState: @unchecked Sendable {
        var lineBuffer = ""   // partial trailing line held until its newline arrives
        var sequence = 0      // monotonic id per parsed entry
    }

    private var process: Process?
    private var pipe: Pipe?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Starts streaming. `-v threadtime` gives a stable, parseable format and
    /// `-T 200` seeds the view with the last 200 lines instead of the entire
    /// (potentially huge) ring buffer before going live.
    ///
    /// - Parameters:
    ///   - onEntries: called on a background queue with each freshly parsed batch.
    ///   - onTerminate: called on a background queue when the process exits.
    func start(
        adbPath: String,
        serial: String,
        onEntries: @escaping @Sendable ([LogEntry]) -> Void,
        onTerminate: @escaping @Sendable () -> Void
    ) throws {
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", serial, "logcat", "-v", "threadtime", "-T", "200"]

        // A fresh pipe per run — a pipe whose write end has closed (previous
        // process exited) is at permanent EOF and cannot be reused.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let stream = StreamState()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

            // Split into complete lines, holding any partial trailing line.
            stream.lineBuffer += chunk
            var lines = stream.lineBuffer.components(separatedBy: "\n")
            stream.lineBuffer = lines.removeLast()   // incomplete remainder (or "" if chunk ended on \n)

            let entries = lines
                .filter { !$0.isEmpty }
                .map { line -> LogEntry in
                    defer { stream.sequence += 1 }
                    return LogEntry.parse(line, id: stream.sequence)
                }
            if !entries.isEmpty { onEntries(entries) }
        }

        // terminationHandler is @Sendable; it captures only the @Sendable callback.
        // Handler detachment happens in stop().
        process.terminationHandler = { _ in onTerminate() }

        try process.run()
        self.process = process
        self.pipe = pipe
    }

    /// Terminates the stream and detaches handlers. Safe to call repeatedly.
    func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
        pipe = nil
    }
}
