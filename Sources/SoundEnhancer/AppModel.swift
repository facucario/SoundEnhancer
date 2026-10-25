import AppKit
import CoreAudio
import Foundation
import os
import SwiftUI

private let modelLog = Logger(subsystem: "com.fcario.soundenhancer", category: "AppModel")

final class AppModel: ObservableObject {

    private enum SettingKey: String {
        case isEnabled
        case intensity
        case useAdvanced
        case width
        case bassDb
        case trebleDb
        case spatial
        case xtcEnabled
        case xtcGeometry
        case xtcIntensity
        case customSeparation
        case customDistance
        case bufferSize
    }

    private static let defaults = UserDefaults.standard

    private static func load<T>(_ key: SettingKey, _ fallback: T) -> T {
        defaults.object(forKey: key.rawValue) as? T ?? fallback
    }

    private static func save(_ value: Any, _ key: SettingKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    @Published var isEnabled: Bool = true {
        didSet { Self.save(isEnabled, .isEnabled) }
    }
    @Published var intensity: Double = 0.5 {
        didSet { Self.save(intensity, .intensity) }
    }

    @Published var useAdvanced: Bool = false {
        didSet { Self.save(useAdvanced, .useAdvanced) }
    }
    @Published var width: Double = 1.6 {
        didSet { Self.save(width, .width) }
    }
    @Published var bassDb: Double = 3.0 {
        didSet { Self.save(bassDb, .bassDb) }
    }
    @Published var trebleDb: Double = 3.5 {
        didSet { Self.save(trebleDb, .trebleDb) }
    }
    @Published var spatial: Double = 12.5 {
        didSet { Self.save(spatial, .spatial) }
    }

    @Published var xtcEnabled: Bool = false {
        didSet { Self.save(xtcEnabled, .xtcEnabled) }
    }
    @Published var xtcGeometry: XTCGeometry = .macBook {
        didSet { Self.save(xtcGeometry.rawValue, .xtcGeometry) }
    }
    @Published var xtcIntensity: Double = 0.8 {
        didSet { Self.save(xtcIntensity, .xtcIntensity) }
    }
    @Published var customSeparation: Double = 0.60 {
        didSet { Self.save(customSeparation, .customSeparation) }
    }
    @Published var customDistance: Double = 0.80 {
        didSet { Self.save(customDistance, .customDistance) }
    }

    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedOutputDeviceID: AudioDeviceID = 0
    @Published var captureSourceText: String?
    @Published var needsDriverInstall: Bool = false
    @Published var bufferSize: Int = 256 {
        didSet { Self.save(bufferSize, .bufferSize) }
    }
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
    private var wakeRetryCount = 0
    private var devicePollTick = 0
    private var isVirtualDefault = false
    private var hasCheckedActivation = false
    private var hasForcedInitialReconnect = false
    private var wakeObserver: NSObjectProtocol?
    private var willTerminateObserver: NSObjectProtocol?
    private let selectedOutputKey = "selectedOutputDeviceID"
    private let selectedOutputUIDKey = "selectedOutputDeviceUID"
    private let selectedOutputNameKey = "selectedOutputDeviceName"
    private let previousDefaultOutputKey = "previousDefaultOutputDeviceID"
    private var previousVolumeDb: Float = 0
    private var previousMute: Bool = false

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

    // The selected output is remembered by UID (and name as a fallback) so it
    // survives the device being re-enumerated with a new AudioDeviceID or even a
    // changed UID (e.g. a DisplayPort/USB monitor after the system wakes).
    private var selectedOutputDeviceUID: String {
        get { UserDefaults.standard.string(forKey: selectedOutputUIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: selectedOutputUIDKey) }
    }

    private var selectedOutputDeviceName: String {
        get { UserDefaults.standard.string(forKey: selectedOutputNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: selectedOutputNameKey) }
    }

    var estimatedLatencyMs: Int {
        let sr = currentVirtualID.flatMap { AudioDeviceManager.nominalSampleRate($0) } ?? 48000
        guard sr > 0 else { return Int((Double(bufferSize) / 48000 * 1000).rounded()) }
        return Int((Double(bufferSize) / sr * 1000).rounded())
    }

    init() {
        isEnabled = Self.load(.isEnabled, true)
        intensity = Self.load(.intensity, 0.5)
        useAdvanced = Self.load(.useAdvanced, false)
        width = Self.load(.width, 1.6)
        bassDb = Self.load(.bassDb, 3.0)
        trebleDb = Self.load(.trebleDb, 3.5)
        spatial = Self.load(.spatial, 12.5)
        xtcEnabled = Self.load(.xtcEnabled, false)
        xtcGeometry = XTCGeometry(rawValue: Self.load(.xtcGeometry, XTCGeometry.macBook.rawValue)) ?? .macBook
        xtcIntensity = Self.load(.xtcIntensity, 0.8)
        customSeparation = Self.load(.customSeparation, 0.60)
        customDistance = Self.load(.customDistance, 0.80)
        bufferSize = Self.load(.bufferSize, 256)

        if let saved = UserDefaults.standard.object(forKey: selectedOutputKey) as? Int {
            selectedOutputDeviceID = AudioDeviceID(saved)
        }
        refreshDevices()
        AudioDeviceManager.addDeviceChangeListener { [weak self] in
            self?.devicesChanged()
        }
        AudioDeviceManager.addDefaultOutputChangeListener { [weak self] in
            self?.refreshActivation()
        }
        // The block-based observers must be retained, otherwise the notification
        // center deallocates them and the wake handler never fires.
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restoreDefaultOutput()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
        syncDriver()
        refreshActivation()
    }

    deinit {
        levelTimer?.invalidate()
    }

    // The app only needs to do work while the SoundEnhancer virtual device is
    // actually in the audio path (i.e. it is the system default output). When
    // the user has routed audio elsewhere (internal speakers, headphones, etc.)
    // the driver's IO is already idle, so we drop to a slow "are we active yet?"
    // poll instead of the 0.5s level-meter / re-sync cadence.
    private func refreshActivation() {
        guard let virtualID = currentVirtualID, virtualID != 0 else {
            setActive(false)
            return
        }
        setActive(AudioDeviceManager.defaultOutputDeviceID() == virtualID)
    }

    private func setActive(_ active: Bool) {
        let changed = (active != isVirtualDefault) || !hasCheckedActivation
        hasCheckedActivation = true
        guard changed else { return }

        let wasActive = isVirtualDefault
        isVirtualDefault = active
        AudioLog.write("app \(active ? "active" : "idle")")

        if active, !wasActive {
            // The enhancer just came back into the path; re-resolve the target.
            syncDriver()
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        levelTimer?.invalidate()
        let interval: TimeInterval = isVirtualDefault ? 0.5 : 3.0
        levelTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }

    private func timerTick() {
        refreshActivation()
        guard isVirtualDefault else { return }

        applySystemVolume()
        refreshLevels()

        // The device-change listener is not always delivered after a monitor's
        // USB-C/DisplayPort audio device is dropped during deep sleep, so the
        // driver can be left pointing at a stale AudioDeviceID that no longer
        // exists (AudioDeviceCreateIOProcID then fails with
        // kAudioHardwareBadDeviceError). Re-sync on a slow cadence so a dead
        // target is re-resolved and a re-appeared monitor is re-selected.
        // (Every 5s; the wake retry loop drives a faster cadence right after
        // sleep, so this only needs to be a background safety net.)
        devicePollTick += 1
        if devicePollTick % 10 == 0 {
            syncDriver()
        }
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
        if selectedOutputDeviceID == 0 {
            selectedOutputDeviceUID = ""
            selectedOutputDeviceName = ""
        } else if let device = outputDevices.first(where: { $0.id == selectedOutputDeviceID }) {
            selectedOutputDeviceUID = device.uid
            selectedOutputDeviceName = device.name
        }
        currentTargetOutputID = 0
        syncDriver()
        // Force the driver to tear down and re-bind its pass-through output IO
        // proc. This recovers from a DisplayPort/HDMI output that was already
        // bound to the driver but stopped producing audio after sleep.
        if let virtualID = currentVirtualID {
            DriverLink.reconnectOutput(to: virtualID)
        }
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
            AudioDeviceManager.setVolumeDecibels(saved, previousVolumeDb)
            AudioDeviceManager.setMuted(saved, previousMute)
            AudioDeviceManager.setDefaultOutputDevice(saved)
            modelLog.info("restored default output to \(saved)")
        }
    }

    // The system woke from sleep. coreaudiod stops the physical output device's
    // IO during sleep, and the driver's pass-through IO proc is not automatically
    // restarted, so the enhancer keeps receiving audio but nothing comes out.
    // Re-resolve the target device and force the driver to re-bind its output.
    private func handleWake() {
        AudioLog.write("wake: reconnecting output")
        wakeRetryCount = 0
        reconnectOutput()
    }

    private func reconnectOutput() {
        syncDriver()

        // On the first attempt after wake, make sure the virtual device is still
        // the system default. coreaudiod can revert the default to the built-in
        // speakers while the machine sleeps, which would bypass the enhancer.
        if wakeRetryCount == 0 {
            reassertVirtualAsDefault()
        }

        // Force a full tear-down and re-bind of the driver's output IO proc for
        // the first few attempts. After that just keep re-syncing so a device
        // that re-appears (with a new ID) gets re-selected and re-bound.
        if wakeRetryCount < 6, let virtualID = currentVirtualID {
            if DriverLink.reconnectOutput(to: virtualID) {
                AudioLog.write("wake: output reconnected to \(currentTargetOutputID ?? 0)")
            } else {
                AudioLog.write("wake: failed to reconnect output")
            }
        }
        wakeRetryCount += 1
        if wakeRetryCount < 30 {
            let delay = wakeRetryCount < 6 ? 1.0 : 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reconnectOutput()
            }
        }
    }

    private func reassertVirtualAsDefault() {
        guard let virtualID = currentVirtualID else { return }
        let current = AudioDeviceManager.defaultOutputDeviceID()
        if current != virtualID, current != 0 {
            AudioDeviceManager.setDefaultOutputDevice(virtualID)
            AudioLog.write("wake: restored default output \(current) -> \(virtualID)")
        }
    }

    // MARK: - Internals

    private func refreshDevices() {
        outputDevices = AudioDeviceManager.outputDevices()

        if selectedOutputDeviceID != 0,
           let current = outputDevices.first(where: { $0.id == selectedOutputDeviceID }) {
            selectedOutputDeviceUID = current.uid
            selectedOutputDeviceName = current.name
            return
        }

        // The selected device is gone (it may have been re-enumerated with a new
        // AudioDeviceID after sleep, and its UID may have changed too). Re-resolve
        // it by UID first, then by name, so a monitor that reconnects on a
        // different transport still gets re-selected instead of falling back to
        // the built-in speakers.
        if !selectedOutputDeviceUID.isEmpty,
           let byUID = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID }) {
            selectedOutputDeviceID = byUID.id
            selectedOutputDeviceName = byUID.name
        } else if !selectedOutputDeviceName.isEmpty,
                  let byName = outputDevices.first(where: { $0.name == selectedOutputDeviceName }) {
            selectedOutputDeviceID = byName.id
            selectedOutputDeviceUID = byName.uid
        } else if selectedOutputDeviceID != 0 {
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
                previousVolumeDb = AudioDeviceManager.volumeDecibels(current)
                previousMute = AudioDeviceManager.isMuted(current)

                AudioDeviceManager.setDefaultOutputDevice(virtual.id)

                // Carry the user's volume over to the virtual device and make the
                // physical device a transparent (full-volume) render target so the
                // virtual device owns the user-facing volume and has full headroom.
                AudioDeviceManager.setVolumeDecibels(virtual.id, previousVolumeDb)
                AudioDeviceManager.setMuted(virtual.id, previousMute)
                AudioDeviceManager.setVolume(current, scalar: 1.0)
                AudioDeviceManager.setMuted(current, false)

                // Sync masterGain now so the carried-over volume takes effect
                // immediately instead of waiting for the next level poll.
                applySystemVolume()

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
            AudioLog.write("sync: output \(currentTargetOutputID.map(String.init) ?? "nil") -> \(outputID)")
            currentTargetOutputID = outputID
            AudioDeviceManager.setBufferFrameSize(virtual.id, frames: UInt32(bufferSize))

            // Tell the driver the target's UID. AudioObjectIDs are per HAL
            // connection, so the driver must re-resolve the UID against its own
            // device list before binding the pass-through IO proc.
            if let uid = outputDevices.first(where: { $0.id == outputID })?.uid {
                DriverLink.writeOutputUID(uid, to: virtual.id)
            }
        }

        pushConfig()

        // On launch the virtual device's IO may already be running with a
        // pass-through output proc that coreaudiod stopped while the system was
        // asleep. Force a single re-bind so a monitor that went silent after
        // sleep recovers even when there is no fresh wake event (e.g. quitting
        // and relaunching the app).
        if !hasForcedInitialReconnect {
            hasForcedInitialReconnect = true
            DriverLink.reconnectOutput(to: virtual.id)
        }
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
