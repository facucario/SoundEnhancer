import CoreAudio
import Foundation
import SwiftUI

final class AppModel: ObservableObject {

    @Published var isEnabled: Bool = true
    @Published var intensity: Double = 0.5

    @Published var useAdvanced: Bool = false
    @Published var width: Double = 1.6
    @Published var bassDb: Double = 3.0
    @Published var trebleDb: Double = 3.5
    @Published var spatial: Double = 12.5

    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID = 0
    @Published var inputDeviceName: String?
    @Published var bufferSize: Int = 256
    @Published var statusText: String = ""
    @Published var levelText: String = ""

    let engine = AudioEngine()

    private var activeInputID: AudioDeviceID?
    private var activeOutputID: AudioDeviceID?
    private var activeBufferSize: Int = 0
    private var levelTimer: Timer?
    private let selectedOutputKey = "selectedOutputDeviceID"

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

    func applyBufferSize() {
        syncEngine()
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
    }

    private func resolveOutputID(avoiding input: AudioDevice) -> AudioDeviceID {
        if selectedOutputDeviceID != 0, outputDevices.contains(where: { $0.id == selectedOutputDeviceID }) {
            return selectedOutputDeviceID
        }
        let def = AudioDeviceManager.defaultOutputDeviceID()
        guard def != 0, def != input.id else {
            return physicalOutputID(avoiding: input.id) ?? def
        }
        return def
    }

    private func physicalOutputID(avoiding excluded: AudioDeviceID) -> AudioDeviceID? {
        let candidates = outputDevices.filter { $0.id != excluded }
        return candidates.first(where: { $0.uid.hasPrefix("BuiltIn") })?.id
            ?? candidates.first?.id
    }

    private func syncEngine() {
        guard let input = AudioDeviceManager.blackHoleInputDevice() else {
            inputDeviceName = nil
            if engine.isRunning {
                engine.stop()
                activeInputID = nil
                activeOutputID = nil
                activeBufferSize = 0
            }
            statusText = "BlackHole not installed — system audio cannot be captured."
            return
        }

        let outputID = resolveOutputID(avoiding: input)
        guard outputID != 0 else {
            inputDeviceName = input.displayName
            statusText = "No output device available."
            return
        }

        inputDeviceName = input.displayName
        let needRestart = !engine.isRunning
            || activeInputID != input.id
            || activeOutputID != outputID
            || activeBufferSize != bufferSize

        guard needRestart else { return }

        do {
            try engine.start(inputDeviceID: input.id, outputDeviceID: outputID, bufferSize: UInt32(bufferSize))
            activeInputID = input.id
            activeOutputID = outputID
            activeBufferSize = bufferSize
            applyDSP()
            updateStatus()
        } catch {
            statusText = "Audio engine error: \(error.localizedDescription)"
        }
    }

    private func updateStatus() {
        let sr = engine.sampleRate
        statusText = "\(Int(sr)) Hz · \(bufferSize) frames · ~\(estimatedLatencyMs) ms"
    }
}
