import SwiftUI

@main
struct StokeholdApp: App {
    var body: some Scene {
        MenuBarExtra("stokehold — booting") {
            VStack(alignment: .leading, spacing: 8) {
                Text("stokehold")
                    .font(.headline)
                Text("boilers not yet lit — gauges land next.")
                    .font(.caption)
            }
            .padding()
        }
    }
}
