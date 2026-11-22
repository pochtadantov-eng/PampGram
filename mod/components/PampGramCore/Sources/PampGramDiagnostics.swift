import Foundation

/// A small persistent event log ("Дополнительно → Диагностика") so that what the mod's background
/// features actually did on a device (auto-save steps, local message edits) can be read back
/// without a debugger. Plain text, newest last, capped in size.
public final class PampGramDiagnostics {
    public static let shared = PampGramDiagnostics()

    private let lock = NSLock()
    private let maxBytes = 60 * 1024
    private let formatter: DateFormatter

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm:ss"
        self.formatter = formatter
    }

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("PampGram", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("diagnostics.log")
    }

    public func log(_ tag: String, _ text: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let url = self.fileURL else {
            return
        }
        let line = "\(self.formatter.string(from: Date())) [\(tag)] \(text)\n"
        var data = (try? Data(contentsOf: url)) ?? Data()
        data.append(Data(line.utf8))
        if data.count > self.maxBytes {
            data = data.suffix(self.maxBytes / 2)
            if let newline = data.firstIndex(of: 10) {
                data = data.suffix(from: data.index(after: newline))
            }
        }
        try? data.write(to: url, options: .atomic)
    }

    public func dump() -> String {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let url = self.fileURL, let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return "Журнал пуст: пока ничего не происходило."
        }
        return text
    }

    public func clear() {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let url = self.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
