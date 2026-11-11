import SwiftUI

/// Shared, observable "current look". The camera thread reads `snapshot`, which is lock-protected.
final class LookStore: ObservableObject {
    @Published var params = LookParameters.neutral {
        didSet {
            lock.lock(); _snapshot = params; lock.unlock()
        }
    }
    @Published var activePresetID: String? = "None"

    private let lock = NSLock()
    private var _snapshot = LookParameters.neutral

    /// Thread-safe copy of the current parameters (safe to call from camera/video queues).
    var snapshot: LookParameters {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
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
