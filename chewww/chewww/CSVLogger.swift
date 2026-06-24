//
//  CSVLogger.swift
//  chewww
//
//  Buffered CSV writer to the app's Documents directory. Files become visible
//  and shareable in the Files app — requires UIFileSharingEnabled and
//  LSSupportsOpeningDocumentsInPlace in Info.plist.
//
//  We buffer rows and flush in batches rather than fsync'ing every ~50 Hz
//  sample, then flush on stop.
//
//  PHASE 1: the session label is owned HERE, not on MotionSample. MotionManager
//  builds every MotionSample and is locked unchanged, so the logger — which
//  already owns the file and already receives the label — is the single,
//  natural place to stamp it. We prepend one leading "label" column to the
//  header and the same token to every row, so multiple CSVs concatenate into
//  one training set with a stable leading label column. The label is captured
//  ONCE at `start(label:)` and reused for every row.
//

import Foundation

@MainActor
final class CSVLogger {
    private(set) var fileURL: URL?
    private var handle: FileHandle?
    private var buffer: [String] = []
    private let flushEvery = 100          // rows; ~2 s at 50 Hz
    private(set) var rowCount = 0

    /// The per-row label token for the current session, snapshotted at
    /// `start(label:)`. Single source of truth — never recomputed per sample.
    private var sessionLabel = ""

    /// Documents directory (the one exposed to the Files app).
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Begin a new file named with a label + timestamp. Returns the URL.
    ///
    /// `label` is the resolved session token (e.g. "eating-crunchy", "walking").
    /// We sanitize it so it can never break the `chewww_<label>_<stamp>.csv`
    /// scheme the history view parses: underscores become hyphens, and
    /// commas/newlines (CSV-breaking) are stripped. The same sanitized token is
    /// written into every row's leading `label` column.
    @discardableResult
    func start(label: String) -> URL? {
        let safeLabel = Self.sanitize(label)
        let stamp = Self.fileStamp()
        let name = "chewww_\(safeLabel)_\(stamp).csv"
        let url = Self.documentsDirectory.appendingPathComponent(name)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = try? FileHandle(forWritingTo: url) else { return nil }

        handle = h
        fileURL = url
        sessionLabel = safeLabel          // per-row label, captured once
        buffer.removeAll(keepingCapacity: true)
        rowCount = 0

        // Label column FIRST so files concatenate cleanly later.
        write(line: "label," + MotionSample.csvHeader)
        return url
    }

    func append(_ sample: MotionSample) {
        write(line: sessionLabel + "," + sample.csvRow)
        rowCount += 1
        if buffer.count >= flushEvery { flush() }
    }

    /// Flush remaining rows and close the file. Returns the final URL.
    @discardableResult
    func stop() -> URL? {
        flush()
        try? handle?.close()
        handle = nil
        let url = fileURL
        return url
    }

    // MARK: - Internals

    private func write(line: String) {
        buffer.append(line)
    }

    private func flush() {
        guard let handle, !buffer.isEmpty else { return }
        let chunk = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll(keepingCapacity: true)
        if let data = chunk.data(using: .utf8) {
            handle.write(data)
        }
    }

    /// Make a label token filename-safe AND CSV-safe.
    ///
    /// - Empty -> "session" (defense in depth; the VM blocks empty labels).
    /// - `_` -> `-` so the `chewww_<label>_<stamp>` split stays 4-part.
    /// - `,` and newlines removed so the per-row label column can't shift
    ///   columns or inject rows.
    private static func sanitize(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "session" }
        return trimmed
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    private static func fileStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: Date())
    }
}
