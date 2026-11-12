import SwiftUI
import UniformTypeIdentifiers

struct SliderSpec: Identifiable {
    var id: String { title }
    let title: String
    let key: WritableKeyPath<LookParameters, Double>
    let range: ClosedRange<Double>
}

enum ControlTab: String, CaseIterable, Identifiable {
    case presets = "Presets", lut = "LUT", light = "Light", color = "Color", film = "Film", vhs = "VHS", vignette = "Vignette"
    var id: String { rawValue }

    var sliders: [SliderSpec] {
        switch self {
        case .light:
            return [
                SliderSpec(title: "Exposure", key: \.exposure, range: -2...2),
                SliderSpec(title: "Contrast", key: \.contrast, range: 0.5...1.5),
                SliderSpec(title: "Highlights", key: \.highlightRecovery, range: 0...1),
                SliderSpec(title: "Shadows", key: \.shadowLift, range: -1...1),
                SliderSpec(title: "Fade", key: \.fade, range: 0...1)
            ]
        case .color:
            return [
                SliderSpec(title: "Saturation", key: \.saturation, range: 0...2),
                SliderSpec(title: "Warmth", key: \.warmth, range: -1...1),
                SliderSpec(title: "Tint", key: \.tint, range: -1...1)
            ]
        case .film:
            return [
                SliderSpec(title: "Grain", key: \.grain, range: 0...1),
                SliderSpec(title: "Grain size", key: \.grainSize, range: 0.5...3),
                SliderSpec(title: "Halation", key: \.halation, range: 0...1),
                SliderSpec(title: "Bloom", key: \.bloom, range: 0...1),
                SliderSpec(title: "Sharpness", key: \.sharpness, range: 0...1)
            ]
        case .vhs:
            return [
                SliderSpec(title: "Color bleed", key: \.vhsBleed, range: 0...1),
                SliderSpec(title: "Scanlines", key: \.scanlines, range: 0...1),
                SliderSpec(title: "Tape noise", key: \.tapeNoise, range: 0...1),
                SliderSpec(title: "Softness", key: \.vhsSoftness, range: 0...1)
            ]
        case .vignette:
            return [
                SliderSpec(title: "Amount", key: \.vignette, range: 0...1),
                SliderSpec(title: "Size", key: \.vignetteSize, range: 0...1),
                SliderSpec(title: "Feather", key: \.vignetteFeather, range: 0...1)
            ]
        default:
            return []
        }
    }
}

/// Tabbed controls shared by the camera and the editor.
struct ControlsPanel: View {
    @EnvironmentObject var look: LookStore
    @AppStorage("balutcam.tab") private var tabRaw = ControlTab.presets.rawValue
    private var tab: ControlTab { ControlTab(rawValue: tabRaw) ?? .presets }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ControlTab.allCases) { t in
                        Button(t.rawValue) { tabRaw = t.rawValue }
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(tab == t ? Color.white : Color.white.opacity(0.12), in: Capsule())
                            .foregroundColor(tab == t ? .black : .white)
                    }
                }
                .padding(.horizontal, 12)
            }

            switch tab {
            case .presets: PresetsView()
            case .lut: LUTView()
            default:
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(tab.sliders) { spec in
                            SliderRow(spec: spec)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }
}

struct SliderRow: View {
    @EnvironmentObject var look: LookStore
    let spec: SliderSpec

    var body: some View {
        HStack {
            Text(spec.title)
                .font(.callout)
                .frame(width: 100, alignment: .leading)
                .onTapGesture(count: 2) {
                    look.binding(spec.key).wrappedValue = LookParameters.neutral[keyPath: spec.key]
                }
            Slider(value: look.binding(spec.key), in: spec.range)
            Text(String(format: "%.2f", look.params[keyPath: spec.key]))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .foregroundColor(.white)
    }
}

struct PresetsView: View {
    @EnvironmentObject var look: LookStore
    @EnvironmentObject var presets: PresetStore
    @State private var showSave = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 10) {
            PresetStrip()
            HStack(spacing: 12) {
                Button {
                    newName = ""
                    showSave = true
                } label: {
                    Label("Save current as preset", systemImage: "plus.circle")
                }
                Spacer()
                Button("Reset", role: .destructive) { look.reset() }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            Text("Long-press a custom preset to delete it. Double-tap a slider name to reset that slider.")
                .font(.caption2).foregroundColor(.gray).padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .alert("Save preset", isPresented: $showSave) {
            TextField("Name", text: $newName)
            Button("Save") { presets.save(name: newName, params: look.params) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves all sliders, the selected LUT and its intensity.")
        }
    }
}

struct PresetStrip: View {
    @EnvironmentObject var look: LookStore
    @EnvironmentObject var presets: PresetStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets.all) { preset in
                    Button(preset.name) { look.apply(preset) }
                        .font(.callout)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(look.activePresetID == preset.id ? Color.orange : Color.white.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)
                        .contextMenu {
                            if !preset.isBuiltIn {
                                Button("Delete", role: .destructive) { presets.delete(preset) }
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct LUTView: View {
    @EnvironmentObject var look: LookStore
    @ObservedObject private var library = LUTLibrary.shared
    @State private var importing = false
    @State private var errorText: String?

    private var cubeType: UTType { UTType(filenameExtension: "cube") ?? .data }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Intensity").font(.callout).frame(width: 100, alignment: .leading)
                    Slider(value: look.binding(\.lutIntensity), in: 0...1)
                    Text(String(format: "%.2f", look.params.lutIntensity))
                        .font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
                .foregroundColor(.white)
                .disabled(look.params.lutName == nil)

                row(title: "None", selected: look.params.lutName == nil) { look.setLUT(nil) }
                ForEach(library.items) { item in
                    row(title: item.name, selected: look.params.lutName == item.name) { look.setLUT(item.name) }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                if look.params.lutName == item.name { look.setLUT(nil) }
                                library.delete(item)
                            }
                        }
                }

                HStack {
                    Button { importing = true } label: { Label("Import .cube", systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button { library.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 4)

                Text("Or drop .cube files into Files → On My iPhone → BalutCam → LUTs, then tap Rescan.")
                    .font(.caption2).foregroundColor(.gray)
            }
            .padding(.horizontal, 12)
        }
        .onAppear { library.scan() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [cubeType, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    do { try library.importFile(at: url) }
                    catch { errorText = "\(url.lastPathComponent): \(error.localizedDescription)" }
                }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .alert("Import problem", isPresented: Binding(get: { errorText != nil },
                                                      set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(selected ? Color.orange.opacity(0.35) : Color.white.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.white)
        }
    }
}
