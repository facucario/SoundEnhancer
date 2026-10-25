import CryptoKit
import Foundation
import os

private let installerLog = Logger(subsystem: "com.fcario.soundenhancer", category: "DriverInstaller")

enum DriverInstaller {

    static let bundleName = "SoundEnhancerDriver.driver"
    static let installDirectory = "/Library/Audio/Plug-Ins/HAL"

    static var installedPath: String {
        "\(installDirectory)/\(bundleName)"
    }

    static func bundledURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(bundleName, isDirectory: true)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installedPath)
    }

    private static func infoValue(_ key: String, at path: String) -> String? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist[key] as? String
    }

    private static func version(at path: String) -> String? {
        infoValue("CFBundleVersion", at: path)
    }

    /// Human-readable driver version, preferring the installed copy and falling
    /// back to the bundled one.
    static func driverVersion() -> String? {
        if isInstalled() {
            if let v = infoValue("CFBundleShortVersionString", at: installedPath) { return v }
        }
        guard let bundled = bundledURL() else { return nil }
        return infoValue("CFBundleShortVersionString", at: bundled.path)
    }

    private static func binaryHash(at path: String) -> String? {
        let binPath = (path as NSString).appendingPathComponent("Contents/MacOS/SoundEnhancerDriver")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: binPath)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isUpToDate() -> Bool {
        guard let bundled = bundledURL(), isInstalled() else { return false }
        let bundledVersion = version(at: bundled.path)
        let installedVersion = version(at: installedPath)
        guard bundledVersion != nil, installedVersion == bundledVersion else { return false }
        guard let bundledHash = binaryHash(at: bundled.path),
              let installedHash = binaryHash(at: installedPath) else { return false }
        return bundledHash == installedHash
    }

    /// Installs the driver to /Library/Audio/Plug-Ins/HAL and reloads coreaudiod.
    /// Requires admin privileges (prompts once via the standard dialog).
    @discardableResult
    static func installIfNeeded() -> Bool {
        if isUpToDate() {
            installerLog.info("driver already up to date")
            return true
        }

        guard let bundled = bundledURL(), FileManager.default.fileExists(atPath: bundled.path) else {
            installerLog.error("bundled driver not found")
            return false
        }

        let src = bundled.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        do shell script "mkdir -p '\(installDirectory)' && rm -rf '\(installedPath)' && cp -R '\(src)' '\(installedPath)' && killall coreaudiod" with administrator privileges
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.launch()
        task.waitUntilExit()

        if task.terminationStatus == 0, isInstalled() {
            installerLog.info("driver installed to \(self.installedPath, privacy: .public)")
            return true
        }
        installerLog.error("driver install failed (status \(task.terminationStatus))")
        return false
    }
}
