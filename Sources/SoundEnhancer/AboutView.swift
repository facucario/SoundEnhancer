import AppKit
import SwiftUI

struct AboutView: View {

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var driverVersion: String {
        DriverInstaller.driverVersion() ?? "Not installed"
    }

    var body: some View {
        VStack(spacing: 10) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            Text("Sound Enhancer")
                .font(.title2.bold())

            Text("Real-time DSP for system audio")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                LabeledContent("App version", value: appVersion)
                LabeledContent("Driver version", value: driverVersion)
            }
            .font(.callout)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 260)
    }
}
