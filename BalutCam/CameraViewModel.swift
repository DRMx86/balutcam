import SwiftUI
import AVFoundation

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var presetList: [LUTAdjustment] = LUTAdjustment.defaultPresets()
    @Published var selectedPresetName: String = "Kodak Portra"
    @Published var contrast: Double = 1.08
    @Published var saturation: Double = 1.15
    @Published var brightness: Double = 0.05
    @Published var warmth: Double = 0.10
    @Published var grain: Double = 0.34
    @Published var vignette: Double = 0.25
    @Published var lutStrength: Double = 0.80
    @Published var captureMode: CaptureMode = .photo
    @Published var libraryItems: [MediaAsset] = []
    @Published var availableLUTFiles: [LUTFile] = [
        LUTFile(id: UUID(), name: "kodak-portra.cube", path: "~/Documents/BalutCam/LUTs/kodak-portra.cube"),
        LUTFile(id: UUID(), name: "fuji-400h.cube", path: "~/Documents/BalutCam/LUTs/fuji-400h.cube"),
        LUTFile(id: UUID(), name: "agfa-vista.cube", path: "~/Documents/BalutCam/LUTs/agfa-vista.cube")
    ]
    @Published var status: String = "Ready for capture"

    let cameraController = CameraController()

    func selectPreset(_ adjustment: LUTAdjustment) {
        selectedPresetName = adjustment.name
        contrast = adjustment.contrast
        saturation = adjustment.saturation
        brightness = adjustment.brightness
        warmth = adjustment.warmth
        grain = adjustment.grain
        vignette = adjustment.vignette
        lutStrength = adjustment.lutStrength
    }

    func saveCustomPreset(name: String) {
        let preset = LUTAdjustment(
            id: UUID(),
            name: name,
            contrast: contrast,
            saturation: saturation,
            brightness: brightness,
            warmth: warmth,
            grain: grain,
            vignette: vignette,
            lutStrength: lutStrength,
            isCustom: true
        )
        presetList.insert(preset, at: 0)
        selectedPresetName = name
        status = "Saved preset: \(name)"
    }

    func resetToPreset() {
        if let selected = presetList.first(where: { $0.name == selectedPresetName }) {
            selectPreset(selected)
        }
    }

    func capturePhoto() {
        status = "Capturing still image"
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                status = "Photo captured with current LUT stack"
            }
        }
    }

    func startVideoCapture() {
        status = "Recording video"
        captureMode = .video
    }

    func stopVideoCapture() {
        status = "Video capture stopped"
        captureMode = .photo
    }

    func addLibraryItem(_ item: MediaAsset) {
        libraryItems.insert(item, at: 0)
        status = "Imported \(item.title) from library"
    }

    func removePreset(_ preset: LUTAdjustment) {
        presetList.removeAll { $0.id == preset.id }
        if selectedPresetName == preset.name {
            selectedPresetName = presetList.first?.name ?? "Kodak Portra"
        }
    }
}

enum CaptureMode: String, CaseIterable {
    case photo = "Photo"
    case video = "Video"
}

final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.drmx86.balutcam.camera")
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        configureSession()
    }

    func requestCameraAccess() async {
        let status = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            self.authorizationStatus = status ? .authorized : .denied
        }
    }

    private func configureSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let cameraController: CameraController

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let layer = AVCaptureVideoPreviewLayer(session: cameraController.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
