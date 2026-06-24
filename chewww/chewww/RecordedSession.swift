//
//  RecordedSession.swift
//  chewww
//
//  One previously-recorded CSV on disk, summarized for the history list.
//  We do NOT persist a separate index: the chewww_*.csv files in Documents
//  ARE the database. Every field is derived from the file (its name + a small
//  bounded read), so a fresh scan always reflects on-disk reality — including
//  files the user added/removed via the Files app.
//
//  Reads are cheap and O(1) memory: sample count is a streamed newline byte
//  count, duration is a short tail-read of the last row's `t` column. This
//  avoids materializing multi-MB files (a multi-minute 50 Hz session is tens
//  of thousands of rows), so `loadAll()` stays fast even off the main thread.
//

import Foundation

struct RecordedSession: Identifiable, Hashable, Sendable {
    /// Stable identity = the file URL (unique per file on disk).
    var id: URL { fileURL }

    let fileURL: URL
    let filename: String          // "chewww_eating-crunchy_20260624_153012.csv"

    /// Activity label parsed from the filename, e.g. "eating", "walking".
    let label: String
    /// Texture tag if the label carried one ("crunchy"/"soft"), else nil.
    let texture: String?
    /// When the session was recorded (parsed from the filename stamp; falls
    /// back to the file's creation date if the stamp can't be read).
    let date: Date

    /// Data rows in the file (header excluded). 0 if unreadable/empty.
    let sampleCount: Int
    /// Wall-clock length in seconds, taken from the last row's elapsed-time
    /// (`t`) column — more accurate than file mtimes. 0 if unknown.
    let durationSec: Double

    // MARK: - Display helpers

    /// "eating · crunchy" or just "walking".
    var displayLabel: String {
        if let texture { return "\(label) · \(texture)" }
        return label
    }

    /// "m:ss".
    var durationText: String {
        let total = Int(durationSec.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var dateText: String {
        Self.displayFormatter.string(from: date)
    }

    // MARK: - Discovery

    /// Scan Documents for chewww_*.csv and summarize each, newest first.
    ///
    /// Runs off the main actor: the directory enumeration plus the bounded
    /// per-file reads are cheap, but doing them across many files on the main
    /// thread would hitch the navigation push. Callers `await` this and assign
    /// the result on the main actor.
    static func loadAll() async -> [RecordedSession] {
        let dir = CSVLogger.documentsDirectory
        return await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return urls
                .filter { $0.pathExtension == "csv"
                       && $0.lastPathComponent.hasPrefix("chewww_") }
                .compactMap { RecordedSession(fileURL: $0) }
                .sorted { $0.date > $1.date }   // newest first
        }.value
    }

    // MARK: - Init from a file on disk

    /// Build a summary by parsing the name and reading the file's edges once.
    /// Returns nil only if the name doesn't fit the `chewww_..._stamp` scheme.
    ///
    /// `nonisolated` on purpose: this only touches the file system and local
    /// strings, so it's safe to run off the main actor — which is exactly where
    /// `loadAll()`'s detached scan calls it from.
    nonisolated init?(fileURL: URL) {
        let name = fileURL.lastPathComponent
        // chewww_<label>_<yyyyMMdd>_<HHmmss>.csv
        // The last two underscore-separated tokens are ALWAYS the stamp; the
        // first is "chewww"; everything between is the label. Joining the
        // middle tolerates a stray underscore in the label without dropping
        // the file (the logger sanitizes underscores out, but a Files-app
        // rename could reintroduce one).
        let stem = name.hasSuffix(".csv") ? String(name.dropLast(4)) : name
        let parts = stem.components(separatedBy: "_")
        guard parts.count >= 4, parts[0] == "chewww" else { return nil }

        let rawLabel = parts[1 ..< (parts.count - 2)].joined(separator: "_")
        let stamp = "\(parts[parts.count - 2])_\(parts[parts.count - 1])"  // "20260624_153012"

        // "eating-crunchy" -> label "eating", texture "crunchy".
        if let dash = rawLabel.firstIndex(of: "-") {
            self.label = String(rawLabel[..<dash])
            self.texture = String(rawLabel[rawLabel.index(after: dash)...])
        } else {
            self.label = rawLabel
            self.texture = nil
        }

        self.fileURL = fileURL
        self.filename = name
        self.date = Self.stampFormatter.date(from: stamp)
            ?? (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            ?? Date()

        let (rows, dur) = Self.scan(fileURL)
        self.sampleCount = rows
        self.durationSec = dur
    }

    // MARK: - Bounded file read

    /// Count data rows + read duration without materializing the whole file.
    ///
    /// - rows: streamed count of `\n` bytes, minus the header line. The writer
    ///   ends every flush with a trailing newline, so newline count == total
    ///   lines (header + data rows); data rows = newlines - 1.
    /// - durationSec: tail-read the last ~512 bytes, take the last complete
    ///   line, parse its first column (`t`, elapsed seconds).
    nonisolated private static func scan(_ url: URL) -> (rows: Int, durationSec: Double) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (0, 0) }
        defer { try? handle.close() }

        // --- streamed newline count ---
        var newlines = 0
        while true {
            guard let data = try? handle.read(upToCount: 64 * 1024),
                  !data.isEmpty else { break }
            for byte in data where byte == 0x0A { newlines += 1 }
        }
        let rows = max(0, newlines - 1)   // subtract header line
        guard rows > 0 else { return (0, 0) }

        // --- tail-read the last data line for duration ---
        let durationSec = lastT(handle: handle) ?? 0
        return (rows, durationSec)
    }

    /// Read the final complete line and parse its first column as Double.
    nonisolated private static func lastT(handle: FileHandle) -> Double? {
        guard let end = try? handle.seekToEnd(), end > 0 else { return nil }
        let window: UInt64 = 512
        let start = end > window ? end - window : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        // Drop a trailing newline, then take everything after the previous one.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let lastLine = lines.last else { return nil }
        let firstField = lastLine.split(separator: ",",
                                        maxSplits: 1,
                                        omittingEmptySubsequences: false).first
        return firstField.flatMap { Double($0) }
    }

    // MARK: - Formatters

    /// Matches CSVLogger.fileStamp(): "yyyyMMdd_HHmmss", POSIX.
    nonisolated private static let stampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private static let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
}
