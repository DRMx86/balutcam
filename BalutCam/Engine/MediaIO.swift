import AVFoundation
import CoreImage
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

enum MediaError: LocalizedError {
    case decode, encode, photosDenied, exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .decode: return "Could not read the selected media."
        case .encode: return "Could not encode the processed image."
        case .photosDenied: return "Photo library access is needed to save. Enable it in Settings."
        case .exportFailed(let m): return "Export failed: \(m)"
        }
    }
}

/// Picked video copied to a temp file so AVFoundation can read it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum MediaIO {
    // MARK: Photos

    /// Applies the look at full resolution and returns JPEG data.
    static func processPhoto(data: Data, params: LookParameters, format: OutputFormat = .full) throws -> Data {
        guard let src = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw MediaError.decode
        }
        let pipeline = FilmPipeline.shared
        let framed = format.apply(src, scaleToTarget: false)
        let out = pipeline.apply(framed, params: params, seed: Int.random(in: 0..<10_000))
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        guard let jpeg = pipeline.context.jpegRepresentation(
            of: out, colorSpace: pipeline.colorSpace, options: [quality: 0.95]) else {
            throw MediaError.encode
        }
        return jpeg
    }

    static func ensureAddAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw MediaError.photosDenied }
    }

    static func savePhoto(_ data: Data) async throws {
        try await ensureAddAccess()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }

    static func saveVideo(_ url: URL) async throws {
        try await ensureAddAccess()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: Video (existing clips)

    /// Used both for live preview in the editor and for the final export.
    static func makeVideoComposition(asset: AVAsset, params: LookParameters,
                                     format: OutputFormat = .full) -> AVVideoComposition {
        let comp = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let framed = format.apply(request.sourceImage, scaleToTarget: true)
            let seed = Int(request.compositionTime.seconds * 24)
            let out = FilmPipeline.shared.apply(framed, params: params, seed: seed)
            request.finish(with: out, context: FilmPipeline.shared.context)
        })
        if format != .full, let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            if let target = format.videoSize(landscape: abs(size.width) > abs(size.height)) {
                comp.renderSize = target
            }
        }
        return comp
    }

    static func exportVideo(url: URL, params: LookParameters, format: OutputFormat = .full,
                            progress: @escaping (Float) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaError.exportFailed("Could not create export session.")
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("filmlab-\(UUID().uuidString).mov")
        session.outputURL = out
        session.outputFileType = .mov
        session.videoComposition = makeVideoComposition(asset: asset, params: params, format: format)

        let poller = Task {
            while !Task.isCancelled {
                progress(session.progress)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        poller.cancel()

        guard session.status == .completed else {
            throw MediaError.exportFailed(session.error?.localizedDescription ?? "unknown error")
        }
        progress(1)
        return out
    }
}
