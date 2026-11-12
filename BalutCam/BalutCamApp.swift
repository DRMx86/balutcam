import SwiftUI

@main
struct BalutCamApp: App {
    @StateObject private var look = LookStore()
    @StateObject private var presets = PresetStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .environmentObject(look)
                .environmentObject(presets)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}
