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

    let engine = AudioEngine()

    private var activeInputID: AudioDeviceID?
    private var activeOutputID: AudioDeviceID?
    private var activeBufferSize: Int = 0
    private var currentVirtualID: AudioDeviceID?
    private var isRestoringOutput = false
    private var installInProgress = false
    private var hasAttemptedAutoInstall = false
    private var lastAutoRestart = Date()
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
        let sr = engine.sampleRate > 0 ? engine.sampleRate : 48000
        return Int((Double(bufferSize) / sr * 1000.0).rounded())
    }

    init() {
        if let saved = UserDefaults.standard.object(forKey: selectedOutputKey) as? Int {
            selectedOutputDeviceID = AudioDeviceID(saved)
        }
        refreshDevices()
        AudioDeviceManager.addDeviceChangeListener { [weak self] in
            self?.devicesChanged()
        }
        AudioDeviceManager.addDefaultOutputChangeListener { [weak self] in
            self?.defaultOutputChanged()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restoreDefaultOutput()
        }
        syncEngine()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateLevels()
        }
    }

    deinit {
        levelTimer?.invalidate()
    }

    private func updateLevels() {
        let inDb = dbString(engine.inputLevel)
        let outDb = dbString(engine.outputLevel)
        levelText = "In \(inDb) · Out \(outDb)"
        applySystemVolume()
        reassertRouting()
        if engine.isRunning, engine.inputLevel < 0.0001, Date().timeIntervalSince(lastAutoRestart) > 10 {
            lastAutoRestart = Date()
            restartEngine()
        }
        if !engine.isRunning {
            syncEngine()
        }
    }

    private func applySystemVolume() {
        guard let virtualID = currentVirtualID else { return }
        let db = AudioDeviceManager.volumeDecibels(virtualID)
        let muted = AudioDeviceManager.isMuted(virtualID)
        let gain: Float = muted ? 0.0 : powf(10.0, db / 20.0)
        engine.setMasterGain(gain)
    }

    private func restartEngine() {
        guard let inID = activeInputID, let outID = activeOutputID else { return }
        do {
            try engine.start(inputDeviceID: inID, outputDeviceID: outID, bufferSize: UInt32(bufferSize))
            applyDSP()
            applyXTC()
            updateStatus()
            AudioLog.write("auto-restart: engine restarted (input silent)")
        } catch {
            statusText = "Audio engine error: \(error.localizedDescription)"
        }
    }

    private func dbString(_ level: Float) -> String {
        guard level > 0.0000001 else { return "-∞ dB" }
        return String(format: "%+.1f dB", 20.0 * log10f(level))
    }

    func applyDSP() {
        guard isEnabled else {
            engine.setParameters(width: 1.0, bassDb: 0, trebleDb: 0, spatialMix: 0)
            return
        }
        if useAdvanced {
            engine.setParameters(
                width: Float(width),
                bassDb: Float(bassDb),
                trebleDb: Float(trebleDb),
                spatialMix: Float(spatial / 100.0))
        } else {
            let a = intensity
            engine.setParameters(
                width: Float(1.0 + 2.0 * a),
                bassDb: Float(10.0 * a),
                trebleDb: Float(10.0 * a),
                spatialMix: Float(0.35 * a))
        }
    }

    func applyOutputSelection() {
        UserDefaults.standard.set(Int(selectedOutputDeviceID), forKey: selectedOutputKey)
        syncEngine()
    }

    func applyXTC() {
        engine.setXTCEnabled(xtcEnabled)
        let (s, d) = xtcGeometryValues()
        engine.setXTCGeometry(separation: s, distance: d)
        engine.setXTCIntensity(Float(xtcIntensity))
    }

    func applyBufferSize() {
        syncEngine()
    }

    func installDriver() {
        guard !installInProgress else { return }
        installInProgress = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            DriverInstaller.installIfNeeded()
            DispatchQueue.main.async {
                guard let self else { return }
                self.installInProgress = false
                self.syncEngine()
            }
        }
    }

    func restoreDefaultOutput() {
        isRestoringOutput = true
        defer { isRestoringOutput = false }
        let saved = previousDefaultOutputID
        guard saved != 0 else { return }
        if AudioDeviceManager.defaultOutputDeviceID() != saved {
            AudioDeviceManager.setDefaultOutputDevice(saved)
            modelLog.info("restored default output to \(saved)")
        }
    }

    private func xtcGeometryValues() -> (separation: Double, distance: Double) {
        if xtcGeometry == .custom {
            return (customSeparation, customDistance)
        }
        return (xtcGeometry.separation, xtcGeometry.distance)
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
        syncEngine()
    }

    private func defaultOutputChanged() {
        if selectedOutputDeviceID == 0 {
            syncEngine()
        }
        reassertRouting()
    }

    private func resolveOutputID(avoiding excluded: AudioDeviceID) -> AudioDeviceID {
        if selectedOutputDeviceID != 0, selectedOutputDeviceID != excluded,
           outputDevices.contains(where: { $0.id == selectedOutputDeviceID }) {
            return selectedOutputDeviceID
        }
        if previousDefaultOutputID != 0, previousDefaultOutputID != excluded,
           outputDevices.contains(where: { $0.id == previousDefaultOutputID }) {
            return previousDefaultOutputID
        }
        return physicalOutputID(avoiding: excluded) ?? 0
    }

    private func physicalOutputID(avoiding excluded: AudioDeviceID) -> AudioDeviceID? {
        let candidates = outputDevices.filter { $0.id != excluded }
        return candidates.first(where: { $0.uid.hasPrefix("BuiltIn") })?.id
            ?? candidates.first?.id
    }

    private func reassertRouting() {
        guard !isRestoringOutput, let virtualID = currentVirtualID else { return }
        let current = AudioDeviceManager.defaultOutputDeviceID()
        if current != virtualID, current != 0 {
            if previousDefaultOutputID == 0 {
                previousDefaultOutputID = current
            }
            AudioDeviceManager.setDefaultOutputDevice(virtualID)
            AudioLog.write("re-route: default \(current) -> \(virtualID)")
        }
    }

    private func syncEngine() {
        refreshDevices()

        if !DriverInstaller.isUpToDate() {
            needsDriverInstall = true
            captureSourceText = nil
            statusText = "SoundEnhancer audio driver needs to be installed or updated."
            AudioLog.write("sync: driver not installed or outdated")
            stopEngine()
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
            stopEngine()
            return
        }

        needsDriverInstall = false
        currentVirtualID = virtual.id
        reassertRouting()

        let outputID = resolveOutputID(avoiding: virtual.id)
        guard outputID != 0 else {
            captureSourceText = virtual.displayName
            statusText = "No physical output device available."
            return
        }

        captureSourceText = virtual.displayName

        let needRestart = !engine.isRunning
            || activeInputID != virtual.id
            || activeOutputID != outputID
            || activeBufferSize != bufferSize

        guard needRestart else { return }

        do {
            try engine.start(inputDeviceID: virtual.id, outputDeviceID: outputID, bufferSize: UInt32(bufferSize))
            activeInputID = virtual.id
            activeOutputID = outputID
            activeBufferSize = bufferSize
            applyDSP()
            applyXTC()
            updateStatus()
            AudioLog.write("sync: engine started in=\(virtual.id) out=\(outputID)")
        } catch {
            statusText = "Audio engine error: \(error.localizedDescription)"
            AudioLog.write("sync: engine error \(error)")
        }
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
            activeInputID = nil
            activeOutputID = nil
            activeBufferSize = 0
        }
    }

    private func updateStatus() {
        let sr = engine.sampleRate
        statusText = "\(Int(sr)) Hz · \(bufferSize) frames · ~\(estimatedLatencyMs) ms"
    }
}
