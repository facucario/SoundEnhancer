import Foundation

enum AudioLog {
    static let path = "/tmp/soundenhancer.log"

    private static let lock = NSLock()

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "[\(Date())] \(message)\n"
        let url = URL(fileURLWithPath: path)
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
