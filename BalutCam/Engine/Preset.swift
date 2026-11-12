import Foundation

struct Preset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var params: LookParameters
    var isBuiltIn: Bool = false
}

final class PresetStore: ObservableObject {
    @Published private(set) var userPresets: [Preset] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("presets.json")
        load()
    }

    var all: [Preset] { Self.builtIn + userPresets }

    func save(name: String, params: LookParameters) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let i = userPresets.firstIndex(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            userPresets[i].params = params
        } else {
            userPresets.append(Preset(id: UUID().uuidString, name: trimmed, params: params))
        }
        persist()
    }

    func delete(_ preset: Preset) {
        userPresets.removeAll { $0.id == preset.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        userPresets = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(userPresets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Built-in looks (approximations by eye, not official stock profiles)

    private static func make(_ name: String, _ tweak: (inout LookParameters) -> Void) -> Preset {
        var p = LookParameters()
        tweak(&p)
        return Preset(id: name, name: name, params: p, isBuiltIn: true)
    }

    static let builtIn: [Preset] = [
        make("None") { _ in },
        make("Gold 200") {
            $0.warmth = 0.45; $0.saturation = 1.15; $0.contrast = 1.08; $0.fade = 0.12
            $0.shadowLift = 0.1; $0.halation = 0.15; $0.bloom = 0.1; $0.vignette = 0.25
        },
        make("Portra 400") {
            $0.warmth = 0.2; $0.tint = -0.05; $0.saturation = 0.92; $0.contrast = 0.95; $0.fade = 0.15
            $0.shadowLift = 0.25; $0.highlightRecovery = 0.3; $0.vignette = 0.15
        },
        make("Ektar 100") {
            $0.warmth = 0.1; $0.saturation = 1.4; $0.contrast = 1.2; $0.vignette = 0.2
        },
        make("Ultramax 400") {
            $0.warmth = 0.35; $0.saturation = 1.25; $0.contrast = 1.12; $0.grainSize = 1.2
            $0.halation = 0.2; $0.vignette = 0.3
        },
        make("ColorPlus 200") {
            $0.warmth = 0.5; $0.tint = 0.08; $0.saturation = 1.05; $0.contrast = 1.05; $0.fade = 0.18
            $0.vignette = 0.3
        },
        make("Vision3 500T") {
            $0.warmth = -0.25; $0.tint = -0.05; $0.contrast = 1.05; $0.fade = 0.08; 
            $0.halation = 0.45; $0.bloom = 0.2; $0.vignette = 0.2
        },
        make("Tri-X 400 B&W") {
            $0.saturation = 0; $0.contrast = 1.3; $0.fade = 0.05; $0.grainSize = 1.3
            $0.vignette = 0.3
        },
        make("Disposable Flash") {
            $0.exposure = 0.15; $0.warmth = 0.3; $0.saturation = 1.2; $0.contrast = 1.2
            $0.highlightRecovery = 0.1; $0.bloom = 0.25; $0.halation = 0.2
            $0.vignette = 0.55; $0.vignetteSize = 0.35
        }
        ,
        // VHS looks (grain stays at 0 like every preset; use the Film tab to add it)
        make("VHS 1989") {
            $0.warmth = 0.15; $0.saturation = 1.2; $0.contrast = 0.95; $0.fade = 0.2; $0.shadowLift = 0.15
            $0.vhsBleed = 0.6; $0.scanlines = 0.35; $0.tapeNoise = 0.25; $0.vhsSoftness = 0.35; $0.vignette = 0.2
        },
        make("VHS Camcorder") {
            $0.saturation = 1.3; $0.tint = -0.05; $0.contrast = 1.05; $0.exposure = 0.1; $0.highlightRecovery = 0.1
            $0.bloom = 0.3; $0.vhsBleed = 0.5; $0.scanlines = 0.2; $0.tapeNoise = 0.1; $0.vhsSoftness = 0.25
        },
        make("Worn Tape") {
            $0.warmth = -0.1; $0.saturation = 0.8; $0.contrast = 0.9; $0.fade = 0.3; $0.shadowLift = 0.2
            $0.vhsBleed = 0.8; $0.scanlines = 0.45; $0.tapeNoise = 0.6; $0.vhsSoftness = 0.5; $0.vignette = 0.35
        },
        make("Cold VHS") {
            $0.warmth = -0.35; $0.tint = 0.1; $0.saturation = 1.1; $0.fade = 0.2
            $0.vhsBleed = 0.55; $0.scanlines = 0.3; $0.tapeNoise = 0.3; $0.vhsSoftness = 0.3; $0.vignette = 0.25
        }
    ]
}
