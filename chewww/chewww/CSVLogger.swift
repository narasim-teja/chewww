//
//  CSVLogger.swift
//  chewww
//
//  Buffered CSV writer to the app's Documents directory. Files become visible
//  and shareable in the Files app — requires UIFileSharingEnabled and
//  LSSupportsOpeningDocumentsInPlace in Info.plist.
//
//  We buffer rows and flush in batches rather than fsync'ing every ~25 Hz
//  sample, then flush on stop.
//

import Foundation

@MainActor
final class CSVLogger {
    private(set) var fileURL: URL?
    private var handle: FileHandle?
    private var buffer: [String] = []
    private let flushEvery = 100          // rows; ~4 s at 25 Hz
    private(set) var rowCount = 0

    /// Documents directory (the one exposed to the Files app).
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Begin a new file named with a label + timestamp. Returns the URL.
    @discardableResult
    func start(label: String) -> URL? {
        let stamp = Self.fileStamp()
        let safeLabel = label.isEmpty ? "session" : label
        let name = "chewww_\(safeLabel)_\(stamp).csv"
        let url = Self.documentsDirectory.appendingPathComponent(name)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = try? FileHandle(forWritingTo: url) else { return nil }

        handle = h
        fileURL = url
        buffer.removeAll(keepingCapacity: true)
        rowCount = 0

        write(line: MotionSample.csvHeader)
        return url
    }

    func append(_ sample: MotionSample) {
        write(line: sample.csvRow)
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

    private static func fileStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: Date())
    }
}
