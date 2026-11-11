import Foundation

/// Every adjustable value of a "look". Codable so presets can be saved as JSON.
struct LookParameters: Codable, Equatable {
    var lutName: String? = nil
    var lutIntensity: Double = 1.0

    // Light
    var exposure: Double = 0          // EV, -2...2
    var contrast: Double = 1          // 0.5...1.5
    var highlightRecovery: Double = 0 // 0...1
    var shadowLift: Double = 0        // -1...1
    var fade: Double = 0              // 0...1 (lifted blacks)

    // Color
    var saturation: Double = 1        // 0...2
    var warmth: Double = 0            // -1...1
    var tint: Double = 0              // -1 (green) ... 1 (magenta)

    // Film
    var grain: Double = 0             // 0...1
    var grainSize: Double = 1         // 0.5...3
    var halation: Double = 0          // 0...1 (red glow around highlights)
    var bloom: Double = 0             // 0...1
    var sharpness: Double = 0         // 0...1

    // Vignette
    var vignette: Double = 0          // 0...1
    var vignetteSize: Double = 0.5    // 0...1 (bigger = larger clear centre)
    var vignetteFeather: Double = 0.5 // 0...1

    static let neutral = LookParameters()
}
