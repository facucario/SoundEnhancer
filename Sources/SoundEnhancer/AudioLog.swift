import Foundation

enum AudioLog {
    static let path = "/tmp/soundenhancer.log"
    static let maxBytes = 256 * 1024

    private static let lock = NSLock()

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let url = URL(fileURLWithPath: path)
        var existing = (try? Data(contentsOf: url)) ?? Data()
        existing.append(data)

        // Keep only the tail so the log never grows without bound.
        if existing.count > maxBytes {
            let drop = existing.count - maxBytes
            existing = existing.subdata(in: drop..<existing.count)
            // Snap to the next line boundary to avoid a partial first line.
            if let newline = existing.firstIndex(of: 0x0A) {
                existing = existing.subdata(in: existing.index(after: newline)..<existing.count)
            }
        }

        try? existing.write(to: url)
    }
}
