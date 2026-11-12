import Foundation

/// Every adjustable value of a "look". Codable so presets and the last-used state can be saved as JSON.
/// Decoding tolerates missing keys, so presets saved by older versions keep working.
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

    // VHS
    var vhsBleed: Double = 0          // 0...1 horizontal colour smear + channel misalignment
    var scanlines: Double = 0         // 0...1
    var tapeNoise: Double = 0         // 0...1 horizontal tape streaks
    var vhsSoftness: Double = 0       // 0...1

    // Vignette
    var vignette: Double = 0          // 0...1
    var vignetteSize: Double = 0.5    // 0...1 (bigger = larger clear centre)
    var vignetteFeather: Double = 0.5 // 0...1

    static let neutral = LookParameters()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get(_ key: CodingKeys, _ fallback: Double) -> Double {
            (try? c.decodeIfPresent(Double.self, forKey: key)) ?? fallback
        }
        lutName = (try? c.decodeIfPresent(String.self, forKey: .lutName)) ?? nil
        lutIntensity = get(.lutIntensity, 1)
        exposure = get(.exposure, 0)
        contrast = get(.contrast, 1)
        highlightRecovery = get(.highlightRecovery, 0)
        shadowLift = get(.shadowLift, 0)
        fade = get(.fade, 0)
        saturation = get(.saturation, 1)
        warmth = get(.warmth, 0)
        tint = get(.tint, 0)
        grain = get(.grain, 0)
        grainSize = get(.grainSize, 1)
        halation = get(.halation, 0)
        bloom = get(.bloom, 0)
        sharpness = get(.sharpness, 0)
        vhsBleed = get(.vhsBleed, 0)
        scanlines = get(.scanlines, 0)
        tapeNoise = get(.tapeNoise, 0)
        vhsSoftness = get(.vhsSoftness, 0)
        vignette = get(.vignette, 0)
        vignetteSize = get(.vignetteSize, 0.5)
        vignetteFeather = get(.vignetteFeather, 0.5)
    }
}
