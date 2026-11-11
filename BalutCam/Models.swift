import Foundation
import SwiftUI

struct LUTAdjustment: Identifiable, Equatable {
    let id: UUID
    var name: String
    var contrast: Double
    var saturation: Double
    var brightness: Double
    var warmth: Double
    var grain: Double
    var vignette: Double
    var lutStrength: Double
    var isCustom: Bool

    static func defaultPresets() -> [LUTAdjustment] {
        [
            LUTAdjustment(id: UUID(), name: "Kodak Portra", contrast: 1.08, saturation: 1.15, brightness: 0.05, warmth: 0.10, grain: 0.34, vignette: 0.25, lutStrength: 0.80, isCustom: false),
            LUTAdjustment(id: UUID(), name: "Fuji 400H", contrast: 1.18, saturation: 1.12, brightness: 0.02, warmth: -0.04, grain: 0.28, vignette: 0.18, lutStrength: 0.76, isCustom: false),
            LUTAdjustment(id: UUID(), name: "Agfa Vista", contrast: 0.95, saturation: 1.30, brightness: 0.08, warmth: 0.14, grain: 0.42, vignette: 0.30, lutStrength: 0.84, isCustom: false),
            LUTAdjustment(id: UUID(), name: "Classic Mono", contrast: 1.25, saturation: 0.70, brightness: 0.10, warmth: 0.00, grain: 0.45, vignette: 0.36, lutStrength: 0.65, isCustom: false)
        ]
    }
}

struct MediaAsset: Identifiable {
    let id: UUID
    let title: String
    let kind: MediaKind
    let source: String
}

enum MediaKind: String {
    case photo
    case video
}

struct LUTFile: Identifiable {
    let id: UUID
    let name: String
    let path: String
}
