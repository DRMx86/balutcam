import AVFoundation
import CoreImage
import SwiftUI

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case photo = "PHOTO", video = "VIDEO"
    var id: String { rawValue }
}

enum FrameRate: String, CaseIterable, Identifiable, Codable {
    case f23_976, f24, f25, f29_97, f30
    var id: String { rawValue }

    var label: String {
        switch self {
        case .f23_976: return "23.976"
        case .f24: return "24"
        case .f25: return "25"
        case .f29_97: return "29.97"
        case .f30: return "30"
        }
    }

    var fps: Double {
        switch self {
        case .f23_976: return 24000.0 / 1001.0
        case .f24: return 24
        case .f25: return 25
        case .f29_97: return 30000.0 / 1001.0
        case .f30: return 30
        }
    }

    /// Exact NTSC-style timing for 23.976 / 29.97 (1001 based), integers for the rest.
    var frameDuration: CMTime {
        switch self {
        case .f23_976: return CMTime(value: 1001, timescale: 24000)
        case .f24: return CMTime(value: 1, timescale: 24)
        case .f25: return CMTime(value: 1, timescale: 25)
        case .f29_97: return CMTime(value: 1001, timescale: 30000)
        case .f30: return CMTime(value: 1, timescale: 30)
        }
    }
}

/// Social-media friendly output shapes. The ratio follows the device orientation
/// (4:5 becomes 5:4 and 9:16 becomes 16:9 when held sideways).
enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case full, square, fourFive, nineSixteen
    var id: String { rawValue }

    func label(landscape: Bool) -> String {
        switch self {
        case .full: return "Full"
        case .square: return "1:1"
        case .fourFive: return landscape ? "5:4" : "4:5"
        case .nineSixteen: return landscape ? "16:9" : "9:16"
        }
    }

    func detail(landscape: Bool) -> String {
        switch self {
        case .full: return "Full frame (native)"
        case .square: return "Square 1080×1080 (Instagram / Facebook)"
        case .fourFive: return landscape ? "1350×1080 (Instagram / Facebook feed)" : "1080×1350 (Instagram / Facebook feed)"
        case .nineSixteen: return landscape ? "1920×1080 (Facebook / YouTube)" : "1080×1920 (Reels / Stories / TikTok)"
        }
    }

    /// Output size for video (nil = keep the source size).
    func videoSize(landscape: Bool) -> CGSize? {
        switch self {
        case .full: return nil
        case .square: return CGSize(width: 1080, height: 1080)
        case .fourFive: return landscape ? CGSize(width: 1350, height: 1080) : CGSize(width: 1080, height: 1350)
        case .nineSixteen: return landscape ? CGSize(width: 1920, height: 1080) : CGSize(width: 1080, height: 1920)
        }
    }

    /// Centre-crops to the format's aspect ratio; optionally scales to the exact video size.
    func apply(_ image: CIImage, scaleToTarget: Bool) -> CIImage {
        guard self != .full else { return image }
        let e = image.extent
        guard e.width > 0, e.height > 0, !e.isInfinite else { return image }
        let landscape = e.width > e.height

        let ratio: CGFloat
        switch self {
        case .square: ratio = 1
        case .fourFive: ratio = landscape ? 5.0 / 4.0 : 4.0 / 5.0
        case .nineSixteen: ratio = landscape ? 16.0 / 9.0 : 9.0 / 16.0
        case .full: ratio = e.width / e.height
        }

        var cw = e.width, ch = e.height
        if cw / ch > ratio { cw = ch * ratio } else { ch = cw / ratio }
        cw = floor(cw); ch = floor(ch)
        let rect = CGRect(x: e.minX + floor((e.width - cw) / 2),
                          y: e.minY + floor((e.height - ch) / 2),
                          width: cw, height: ch)
        var out = image.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))

        if scaleToTarget, let target = videoSize(landscape: landscape) {
            let sx = target.width / cw, sy = target.height / ch
            if abs(sx - 1) > 0.01 || abs(sy - 1) > 0.01 {
                out = out.applyingFilter("CILanczosScaleTransform", parameters: [
                    "inputScale": sy, "inputAspectRatio": sx / sy
                ])
            }
            out = out.cropped(to: CGRect(origin: .zero, size: target))
        }
        return out
    }
}

struct AppConfig: Codable, Equatable {
    var mode: CaptureMode = .photo
    var format: OutputFormat = .full
    var frameRate: FrameRate = .f30
    var flashOn = false
    var usingFront = false
}

/// Capture settings, remembered between launches. Thread-safe `snapshot` for the camera queues.
final class AppSettings: ObservableObject {
    private static let key = "balutcam.config"

    @Published var config = AppConfig() {
        didSet {
            lock.lock(); _snapshot = config; lock.unlock()
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private let lock = NSLock()
    private var _snapshot = AppConfig()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = saved
            _snapshot = saved
        }
    }

    var snapshot: AppConfig {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
    }
}
