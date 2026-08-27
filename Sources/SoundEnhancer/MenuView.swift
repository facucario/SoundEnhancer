import CoreAudio
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

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

            if let input = model.inputDeviceName {
                Label("Input: \(input)", systemImage: "arrow.down.circle")
                    .font(.caption)
            } else {
                Label("Virtual input not found", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
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
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(minWidth: 280)
    }
}
