import CoreAudio
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enhancer", isOn: $model.isEnabled)
                .onChange(of: model.isEnabled) { _, _ in model.applyDSP() }

            Divider()

            Picker("Output", selection: $model.selectedOutputDeviceID) {
                Text("System Default").tag(AudioDeviceID(0))
                ForEach(model.outputDevices) { device in
                    Text(device.displayName).tag(device.id)
                }
            }
            .onChange(of: model.selectedOutputDeviceID) { _, _ in model.applyOutputSelection() }

            Divider()

            if model.needsDriverInstall {
                Label("Driver not installed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if let source = model.captureSourceText {
                Label("Virtual device: \(source)", systemImage: "waveform")
                    .font(.caption)
            } else {
                Label("Starting…", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(model.statusText)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(model.levelText)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            Button("About Sound Enhancer…") {
                openWindow(id: "about")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Uninstall Sound Enhancer…") {
                model.uninstall()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(minWidth: 280)
    }
}
