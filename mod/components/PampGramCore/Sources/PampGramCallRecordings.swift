import Foundation

/// One saved call recording. The audio itself is a plain `.m4a` file next to the index.
public struct PampGramCallRecordingEntry: Codable, Equatable {
    /// The file name, unique per recording.
    public var id: String
    public var peerId: Int64
    public var title: String
    public var date: Int32
    public var duration: Double
    public var isOutgoing: Bool

    public init(id: String, peerId: Int64, title: String, date: Int32, duration: Double, isOutgoing: Bool) {
        self.id = id
        self.peerId = peerId
        self.title = title
        self.date = date
        self.duration = duration
        self.isOutgoing = isOutgoing
    }
}

private struct PampGramCallRecordingIndex: Codable {
    var entries: [PampGramCallRecordingEntry]
}

/// File-backed list of the call recordings on this device. Kept outside Postbox on purpose: the files
/// are large, belong to the device rather than one account, and are removed together with the index.
public enum PampGramCallRecordingStore {
    private static let lock = NSLock()

    public static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PampGramCallRecordings", isDirectory: true)
    }

    private static var indexURL: URL {
        return self.directoryURL.appendingPathComponent("index.json")
    }

    private static func ensureDirectory() {
        var url = self.directoryURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }

    /// A fresh file for a call that is about to be recorded.
    public static func makeNewFile(peerId: Int64) -> (id: String, path: String) {
        self.ensureDirectory()
        let id = "call-\(Int64(Date().timeIntervalSince1970))-\(abs(peerId)).m4a"
        return (id, self.directoryURL.appendingPathComponent(id).path)
    }

    public static func fileURL(id: String) -> URL {
        return self.directoryURL.appendingPathComponent(id)
    }

    private static func readIndex() -> [PampGramCallRecordingEntry] {
        guard let data = try? Data(contentsOf: self.indexURL), let index = try? JSONDecoder().decode(PampGramCallRecordingIndex.self, from: data) else {
            return []
        }
        return index.entries
    }

    private static func writeIndex(_ entries: [PampGramCallRecordingEntry]) {
        self.ensureDirectory()
        if let data = try? JSONEncoder().encode(PampGramCallRecordingIndex(entries: entries)) {
            try? data.write(to: self.indexURL, options: [.atomic])
        }
    }

    /// Newest first. Entries whose file has gone missing are skipped.
    public static func entries() -> [PampGramCallRecordingEntry] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.readIndex().filter { FileManager.default.fileExists(atPath: self.fileURL(id: $0.id).path) }.sorted(by: { $0.date > $1.date })
    }

    public static func add(_ entry: PampGramCallRecordingEntry) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var entries = self.readIndex()
        entries.removeAll(where: { $0.id == entry.id })
        entries.append(entry)
        self.writeIndex(entries)
    }

    public static func remove(id: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        try? FileManager.default.removeItem(at: self.fileURL(id: id))
        self.writeIndex(self.readIndex().filter { $0.id != id })
    }

    public static func removeAll() {
        self.lock.lock()
        defer { self.lock.unlock() }
        for entry in self.readIndex() {
            try? FileManager.default.removeItem(at: self.fileURL(id: entry.id))
        }
        self.writeIndex([])
    }

    /// A call that produced no usable audio leaves nothing behind.
    public static func discardFile(id: String) {
        try? FileManager.default.removeItem(at: self.fileURL(id: id))
    }

    public static func totalSize() -> Int64 {
        var total: Int64 = 0
        for entry in self.entries() {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: self.fileURL(id: entry.id).path), let size = attributes[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }
}
