import AVKit
import CoreImage
import ImageIO
import PhotosUI
import SwiftUI

/// Grade an existing photo or video from the camera roll and save it as a new file.
struct EditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var look: LookStore

    @State private var pickerItem: PhotosPickerItem?
    @State private var originalPhoto: Data?
    @State private var previewSource: CIImage?
    @State private var previewImage: UIImage?
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var renderTask: Task<Void, Never>?
    @State private var busy = false
    @State private var progress: Float = 0
    @State private var status: String?
    @State private var showControls = true

    private var hasMedia: Bool { originalPhoto != nil || videoURL != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { player?.pause(); dismiss() }
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                    Label("Choose", systemImage: "photo")
                }
                Spacer()
                Button("Save") { Task { await save() } }
                    .disabled(!hasMedia || busy)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            ZStack {
                Color.black
                if let player {
                    VideoPlayer(player: player)
                } else if let previewImage {
                    Image(uiImage: previewImage).resizable().scaledToFit()
                } else {
                    Text("Choose a photo or video").foregroundColor(.gray)
                }
                if busy {
                    VStack(spacing: 8) {
                        ProgressView(value: videoURL != nil ? Double(progress) : nil)
                            .progressViewStyle(.linear).frame(width: 180)
                        Text("Processing…").font(.caption)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if let status {
                Text(status).font(.footnote).padding(.vertical, 6)
            }

            HStack {
                Button {
                    withAnimation { showControls.toggle() }
                } label: {
                    Label(showControls ? "Hide controls" : "Show controls", systemImage: "slider.horizontal.3")
                        .font(.footnote)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            if showControls {
                ControlsPanel().frame(height: 250)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onChange(of: look.params) { params in
            if player != nil { updateVideoComposition(params) } else { renderPreview(params) }
        }
        .onDisappear { player?.pause() }
    }

    // MARK: Loading

    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        status = nil
        player?.pause(); player = nil; videoURL = nil
        originalPhoto = nil; previewSource = nil; previewImage = nil

        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        do {
            if isVideo {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    status = "Could not load video"; return
                }
                videoURL = movie.url
                let playerItem = AVPlayerItem(asset: AVURLAsset(url: movie.url))
                playerItem.videoComposition = MediaIO.makeVideoComposition(asset: playerItem.asset, params: look.params)
                let p = AVPlayer(playerItem: playerItem)
                player = p
                p.play()
            } else {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let src = Self.downscaledImage(data: data, maxPixel: 1600) else {
                    status = "Could not load photo"; return
                }
                originalPhoto = data
                previewSource = src
                renderPreview(look.params)
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private static func downscaledImage(data: Data, maxPixel: Int) -> CIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return CIImage(cgImage: cg)
    }

    // MARK: Live preview

    private func renderPreview(_ params: LookParameters) {
        guard let src = previewSource else { return }
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) {
            let pipeline = FilmPipeline.shared
            let out = pipeline.apply(src, params: params, seed: 1)
            guard !Task.isCancelled,
                  let cg = pipeline.context.createCGImage(out, from: src.extent) else { return }
            await MainActor.run { previewImage = UIImage(cgImage: cg) }
        }
    }

    private func updateVideoComposition(_ params: LookParameters) {
        guard let item = player?.currentItem else { return }
        item.videoComposition = MediaIO.makeVideoComposition(asset: item.asset, params: params)
    }

    // MARK: Saving

    @MainActor
    private func save() async {
        let params = look.params
        busy = true; progress = 0; status = nil
        defer { busy = false }
        do {
            if let data = originalPhoto {
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    try MediaIO.processPhoto(data: data, params: params)
                }.value
                try await MediaIO.savePhoto(jpeg)
                status = "Saved new photo to your library"
            } else if let url = videoURL {
                player?.pause()
                let out = try await MediaIO.exportVideo(url: url, params: params) { value in
                    Task { @MainActor in progress = value }
                }
                try await MediaIO.saveVideo(out)
                try? FileManager.default.removeItem(at: out)
                status = "Saved new video to your library"
                player?.play()
            }
        } catch {
            status = error.localizedDescription
        }
    }
}
