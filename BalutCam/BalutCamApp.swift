import SwiftUI

@main
struct BalutCamApp: App {
    @StateObject private var look = LookStore()
    @StateObject private var presets = PresetStore()

    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .environmentObject(look)
                .environmentObject(presets)
                .preferredColorScheme(.dark)
        }
    }
}
