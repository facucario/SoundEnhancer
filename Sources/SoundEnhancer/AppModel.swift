import AppKit
import CoreAudio
import Foundation
import os
import SwiftUI

private let modelLog = Logger(subsystem: "com.fcario.soundenhancer", category: "AppModel")

final class AppModel: ObservableObject {

    @Published var isEnabled: Bool = true
    @Published var intensity: Double = 0.5

    @Published var useAdvanced: Bool = false
    @Published var width: Double = 1.6
    @Published var bassDb: Double = 3.0
    @Published var trebleDb: Double = 3.5
    @Published var spatial: Double = 12.5

    @Published var xtcEnabled: Bool = false
    @Published var xtcGeometry: XTCGeometry = .macBook
    @Published var xtcIntensity: Double = 0.8
    @Published var customSeparation: Double = 0.60
    @Published var customDistance: Double = 0.80

    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID = 0
    @Published var captureSourceText: String?
    @Published var needsDriverInstall: Bool = false
    @Published var bufferSize: Int = 256
    @Published var statusText: String = ""
    @Published var levelText: String = ""

    private var currentVirtualID: AudioDeviceID?
    private var currentTargetOutputID: AudioDeviceID?
    private var installInProgress = false
    private var hasAttemptedAutoInstall = false
    private var hasAutoSelectedOutput = false
    private var lastPushedMasterGain: Float = -1
    private var lastPushedConfig: SEConfig?
    private var levelTimer: Timer?
    private let selectedOutputKey = "selectedOutputDeviceID"
    private let previousDefaultOutputKey = "previousDefaultOutputDeviceID"

    private var previousDefaultOutputID: AudioDeviceID {
        get {
            if let saved = UserDefaults.standard.object(forKey: previousDefaultOutputKey) as? Int {
                return AudioDeviceID(saved)
            }
            return 0
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: previousDefaultOutputKey)
        }
    }

    var estimatedLatencyMs: Int {
        let sr = currentVirtualID.flatMap { AudioDeviceManager.nominalSampleRate($0) } ?? 48000
        guard sr > 0 else { return Int((Double(bufferSize) / 48000 * 1000).rounded()) }
        return Int((Double(bufferSize) / sr * 1000).rounded())
    }

    init() {
        if let saved = UserDefaults.standard.object(forKey: selectedOutputKey) as? Int {
            selectedOutputDeviceID = AudioDeviceID(saved)
        }
        refreshDevices()
        AudioDeviceManager.addDeviceChangeListener { [weak self] in
            self?.devicesChanged()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restoreDefaultOutput()
        }
        syncDriver()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateLevels()
        }
    }

    deinit {
        levelTimer?.invalidate()
    }

    private func updateLevels() {
        applySystemVolume()
        refreshLevels()
    }

    private func refreshLevels() {
        guard let virtualID = currentVirtualID else { return }
        guard let read = DriverLink.readConfig(from: virtualID) else { return }
        levelText = "In \(dbString(read.inputLevel)) · Out \(dbString(read.outputLevel))"
    }

    private func applySystemVolume() {
        guard let virtualID = currentVirtualID else { return }
        let db = AudioDeviceManager.volumeDecibels(virtualID)
        let muted = AudioDeviceManager.isMuted(virtualID)
        let gain: Float = muted ? 0.0 : powf(10.0, db / 20.0)
        guard abs(gain - lastPushedMasterGain) > 0.0001 else { return }
        lastPushedMasterGain = gain
        pushConfig()
    }

    private func dbString(_ level: Float) -> String {
        guard level > 0.0000001 else { return "-∞ dB" }
        return String(format: "%+.1f dB", 20.0 * log10f(level))
    }

    func applyDSP() {
        pushConfig()
    }

    func applyOutputSelection() {
        UserDefaults.standard.set(Int(selectedOutputDeviceID), forKey: selectedOutputKey)
        currentTargetOutputID = 0
        syncDriver()
    }

    func applyXTC() {
        pushConfig()
    }

    func applyBufferSize() {
        if let virtualID = currentVirtualID {
            AudioDeviceManager.setBufferFrameSize(virtualID, frames: UInt32(bufferSize))
        }
        pushConfig()
    }

    func installDriver() {
        guard !installInProgress else { return }
        installInProgress = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            DriverInstaller.installIfNeeded()
            DispatchQueue.main.async {
                guard let self else { return }
                self.installInProgress = false
                self.syncDriver()
            }
        }
    }

    private func xtcGeometryValues() -> (separation: Double, distance: Double) {
        if xtcGeometry == .custom {
            return (customSeparation, customDistance)
        }
        return (xtcGeometry.separation, xtcGeometry.distance)
    }

    func restoreDefaultOutput() {
        let saved = previousDefaultOutputID
        guard saved != 0 else { return }
        let current = AudioDeviceManager.defaultOutputDeviceID()
        if current != saved {
            AudioDeviceManager.setDefaultOutputDevice(saved)
            modelLog.info("restored default output to \(saved)")
        }
    }

    // MARK: - Internals

    private func refreshDevices() {
        outputDevices = AudioDeviceManager.outputDevices()
        if selectedOutputDeviceID != 0, !outputDevices.contains(where: { $0.id == selectedOutputDeviceID }) {
            selectedOutputDeviceID = 0
        }
    }

    private func devicesChanged() {
        refreshDevices()
        syncDriver()
    }

    private func resolveOutputID(avoiding excluded: AudioDeviceID) -> AudioDeviceID {
        if selectedOutputDeviceID != 0, selectedOutputDeviceID != excluded,
           outputDevices.contains(where: { $0.id == selectedOutputDeviceID }) {
            return selectedOutputDeviceID
        }
        return physicalOutputID(avoiding: excluded) ?? 0
    }

    private func physicalOutputID(avoiding excluded: AudioDeviceID) -> AudioDeviceID? {
        let candidates = outputDevices.filter { $0.id != excluded }
        return candidates.first(where: { $0.uid.hasPrefix("BuiltIn") })?.id
            ?? candidates.first?.id
    }

    private func syncDriver() {
        refreshDevices()

        if !DriverInstaller.isUpToDate() {
            needsDriverInstall = true
            captureSourceText = nil
            currentVirtualID = nil
            statusText = "SoundEnhancer audio driver needs to be installed or updated."
            AudioLog.write("sync: driver not installed or outdated")
            if !hasAttemptedAutoInstall {
                hasAttemptedAutoInstall = true
                installDriver()
            }
            return
        }

        guard let virtual = AudioDeviceManager.virtualDevice() else {
            needsDriverInstall = false
            captureSourceText = nil
            currentVirtualID = nil
            statusText = "Waiting for the SoundEnhancer virtual device…"
            AudioLog.write("sync: virtual device not found")
            return
        }

        needsDriverInstall = false
        currentVirtualID = virtual.id

        if !hasAutoSelectedOutput {
            hasAutoSelectedOutput = true
            let current = AudioDeviceManager.defaultOutputDeviceID()
            if current != virtual.id, current != 0 {
                previousDefaultOutputID = current
                AudioDeviceManager.setDefaultOutputDevice(virtual.id)
                AudioLog.write("auto-select: default \(current) -> \(virtual.id)")
            }
        }

        let outputID = resolveOutputID(avoiding: virtual.id)
        guard outputID != 0 else {
            captureSourceText = virtual.displayName
            statusText = "No physical output device available."
            return
        }

        captureSourceText = virtual.displayName

        if let target = AudioDeviceManager.device(id: outputID), target.nominalSampleRate > 0 {
            let currentRate = AudioDeviceManager.nominalSampleRate(virtual.id)
            if abs(currentRate - target.nominalSampleRate) > 0.5 {
                AudioDeviceManager.setNominalSampleRate(virtual.id, rate: target.nominalSampleRate)
            }
        }

        if currentTargetOutputID != outputID {
            currentTargetOutputID = outputID
            AudioDeviceManager.setBufferFrameSize(virtual.id, frames: UInt32(bufferSize))
        }

        pushConfig()
    }

    private func pushConfig() {
        guard let virtualID = currentVirtualID, let outputID = currentTargetOutputID else { return }

        var cfg = SEConfig()
        cfg.enabled = isEnabled ? 1 : 0
        cfg.outputDeviceID = outputID
        cfg.masterGain = lastPushedMasterGain < 0 ? 1.0 : lastPushedMasterGain

        if useAdvanced {
            cfg.width = Float(width)
            cfg.bassDb = Float(bassDb)
            cfg.trebleDb = Float(trebleDb)
            cfg.spatialMix = Float(spatial / 100.0)
        } else {
            let a = intensity
            cfg.width = Float(1.0 + 2.0 * a)
            cfg.bassDb = Float(10.0 * a)
            cfg.trebleDb = Float(10.0 * a)
            cfg.spatialMix = Float(0.35 * a)
        }

        cfg.xtcEnabled = xtcEnabled ? 1 : 0
        let (s, d) = xtcGeometryValues()
        cfg.xtcIntensity = Float(xtcIntensity)
        cfg.xtcSeparation = Float(s)
        cfg.xtcDistance = Float(d)

        if cfg == lastPushedConfig {
            return
        }

        lastPushedConfig = cfg
        if DriverLink.writeConfig(cfg, to: virtualID) {
            updateStatus()
        } else {
            statusText = "Could not configure the audio driver."
            AudioLog.write("push: failed to write config to \(virtualID)")
        }
    }

    private func updateStatus() {
        let sr = currentVirtualID.flatMap { AudioDeviceManager.nominalSampleRate($0) } ?? 48000
        statusText = "\(Int(sr)) Hz · \(bufferSize) frames · ~\(estimatedLatencyMs) ms"
    }
}
