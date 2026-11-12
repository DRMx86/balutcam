import SwiftUI

/// Shared, observable "current look". Saved to UserDefaults on every change so the app reopens exactly as left.
/// The camera thread reads `snapshot`, which is lock-protected.
final class LookStore: ObservableObject {
    private struct Saved: Codable {
        var params: LookParameters
        var activePresetID: String?
    }
    private static let key = "balutcam.look"

    @Published var params = LookParameters.neutral {
        didSet {
            lock.lock(); _snapshot = params; lock.unlock()
            persist()
        }
    }
    @Published var activePresetID: String? = "None" {
        didSet { persist() }
    }

    private let lock = NSLock()
    private var _snapshot = LookParameters.neutral

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            params = saved.params
            _snapshot = saved.params
            activePresetID = saved.activePresetID
            if let name = saved.params.lutName {
                DispatchQueue.global(qos: .utility).async { _ = LUTLibrary.shared.cube(named: name) }
            }
        }
    }

    /// Thread-safe copy of the current parameters (safe to call from camera/video queues).
    var snapshot: LookParameters {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
    }

    private func persist() {
        let saved = Saved(params: params, activePresetID: activePresetID)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func binding(_ keyPath: WritableKeyPath<LookParameters, Double>) -> Binding<Double> {
        Binding(
            get: { self.params[keyPath: keyPath] },
            set: { self.params[keyPath: keyPath] = $0; self.activePresetID = nil }
        )
    }

    func reset() {
        params = .neutral
        activePresetID = "None"
    }

    func apply(_ preset: Preset) {
        prepareLUT(preset.params.lutName) {
            self.params = preset.params
            self.activePresetID = preset.id
        }
    }

    func setLUT(_ name: String?) {
        prepareLUT(name) {
            self.params.lutName = name
            self.activePresetID = nil
        }
    }

    /// Parses the LUT off the main thread first so the camera never stalls on a big .cube file.
    private func prepareLUT(_ name: String?, then done: @escaping () -> Void) {
        guard let name else { done(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = LUTLibrary.shared.cube(named: name)
            DispatchQueue.main.async(execute: done)
        }
    }
}
