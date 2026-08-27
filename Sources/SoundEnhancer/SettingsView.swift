import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Advanced controls", isOn: $model.useAdvanced)
                    .onChange(of: model.useAdvanced) { _, _ in model.applyDSP() }

                if model.useAdvanced {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Stereo Width") {
                            Text(String(format: "%.2f×", model.width))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.width, in: 1.0...3.0)
                            .onChange(of: model.width) { _, _ in model.applyDSP() }

                        LabeledContent("Bass Boost") {
                            Text(String(format: "+%.1f dB", model.bassDb))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.bassDb, in: 0...10)
                            .onChange(of: model.bassDb) { _, _ in model.applyDSP() }

                        LabeledContent("Treble Boost") {
                            Text(String(format: "+%.1f dB", model.trebleDb))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.trebleDb, in: 0...10)
                            .onChange(of: model.trebleDb) { _, _ in model.applyDSP() }

                        LabeledContent("Spatial Depth") {
                            Text("\(Int(model.spatial))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.spatial, in: 0...35)
                            .onChange(of: model.spatial) { _, _ in model.applyDSP() }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Intensity") {
                            Text("\(Int(model.intensity * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.intensity, in: 0...1)
                            .onChange(of: model.intensity) { _, _ in model.applyDSP() }
                        Text("Adds stereo width, bass and treble warmth as you raise the intensity.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Enhancer")
            }

            Section("Crosstalk Cancellation (XTC)") {
                Toggle("Enable XTC", isOn: $model.xtcEnabled)
                    .onChange(of: model.xtcEnabled) { _, _ in model.applyXTC() }

                if model.xtcEnabled {
                    Picker("Speaker Setup", selection: $model.xtcGeometry) {
                        ForEach(XTCGeometry.allCases) { geometry in
                            Text(geometry.displayName).tag(geometry)
                        }
                    }
                    .onChange(of: model.xtcGeometry) { _, _ in model.applyXTC() }

                    if model.xtcGeometry == .custom {
                        LabeledContent("Speaker separation") {
                            Text(String(format: "%.2f m", model.customSeparation))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.customSeparation, in: 0.1...3.0)
                            .onChange(of: model.customSeparation) { _, _ in model.applyXTC() }

                        LabeledContent("Listener distance") {
                            Text(String(format: "%.2f m", model.customDistance))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.customDistance, in: 0.1...3.0)
                            .onChange(of: model.customDistance) { _, _ in model.applyXTC() }
                    }

                    LabeledContent("Cancellation") {
                        Text("\(Int(model.xtcIntensity * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.xtcIntensity, in: 0...1)
                        .onChange(of: model.xtcIntensity) { _, _ in model.applyXTC() }

                    Text("Cancels acoustic crosstalk between speakers to preserve binaural spatial cues over loudspeakers. Choose the setup that matches your speaker geometry.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Latency") {
                Picker("Buffer Size", selection: $model.bufferSize) {
                    Text("128 frames").tag(128)
                    Text("256 frames").tag(256)
                    Text("512 frames").tag(512)
                    Text("1024 frames").tag(1024)
                }
                .onChange(of: model.bufferSize) { _, _ in model.applyBufferSize() }

                LabeledContent("Estimated latency", value: "~\(model.estimatedLatencyMs) ms")
                Text("Smaller buffers reduce latency but increase the chance of dropouts. 256 is a good default.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Routing") {
                if let input = model.inputDeviceName {
                    LabeledContent("Capture device", value: input)
                } else {
                    Text("Install BlackHole (`brew install blackhole-2ch`) and set your system output to it, then this app will route the captured audio to your speakers or headphones.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
