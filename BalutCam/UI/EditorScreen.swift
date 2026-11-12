import AVKit
import CoreImage
import ImageIO
import PhotosUI
import SwiftUI

/// Grade an existing photo or video from the camera roll and save it as a new file.
struct EditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var look: LookStore
    @EnvironmentObject var settings: AppSettings

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
    @AppStorage("balutcam.editorControls") private var showControls = true

    private var hasMedia: Bool { originalPhoto != nil || videoURL != nil }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                topBar(landscape: landscape)
                if landscape {
                    HStack(spacing: 0) {
                        mediaArea
                        if showControls { ControlsPanel().frame(width: 380) }
                    }
                } else {
                    mediaArea
                    controlsToggle
                    if showControls { ControlsPanel().frame(height: 300) }
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task { await load(item) }
        }
        .onChange(of: look.params) { _ in refresh() }
        .onChange(of: settings.config.format) { _ in refresh() }
        .onDisappear { player?.pause() }
    }

    private func topBar(landscape: Bool) -> some View {
        HStack(spacing: 10) {
            Button("Close") { player?.pause(); dismiss() }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16).frame(height: 48)
                .background(Color.white.opacity(0.12), in: Capsule())

            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                Label("Choose", systemImage: "photo")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }

            Menu {
                Picker("Format", selection: $settings.config.format) {
                    ForEach(OutputFormat.allCases) { f in
                        Text("\(f.label(landscape: landscape)) · \(f.detail(landscape: landscape))").tag(f)
                    }
                }
            } label: {
                Label(settings.config.format.label(landscape: landscape), systemImage: "aspectratio")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }

            Spacer()

            if landscape {
                Button { withAnimation { showControls.toggle() } } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 48, height: 48)
                        .background(showControls ? Color.orange : Color.white.opacity(0.12), in: Circle())
                        .foregroundColor(showControls ? .black : .white)
                }
            }

            Button { Task { await save() } } label: {
                Text("Save").font(.body.weight(.bold))
                    .padding(.horizontal, 22).frame(height: 48)
                    .background(hasMedia && !busy ? Color.orange : Color.white.opacity(0.12), in: Capsule())
                    .foregroundColor(hasMedia && !busy ? .black : .gray)
            }
            .disabled(!hasMedia || busy)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var mediaArea: some View {
        ZStack(alignment: .bottom) {
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
                .frame(maxHeight: .infinity)
            }
            if let status {
                Text(status).font(.footnote).padding(8)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controlsToggle: some View {
        HStack {
            Button { withAnimation { showControls.toggle() } } label: {
                Label(showControls ? "Hide controls" : "Show controls", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
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
                playerItem.videoComposition = MediaIO.makeVideoComposition(
                    asset: playerItem.asset, params: look.params, format: settings.config.format)
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
                renderPreview()
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

    private func refresh() {
        if player != nil { updateVideoComposition() } else { renderPreview() }
    }

    private func renderPreview() {
        guard let src = previewSource else { return }
        let params = look.params
        let format = settings.config.format
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) {
            let pipeline = FilmPipeline.shared
            let framed = format.apply(src, scaleToTarget: false)
            let out = pipeline.apply(framed, params: params, seed: 1)
            guard !Task.isCancelled,
                  let cg = pipeline.context.createCGImage(out, from: framed.extent) else { return }
            await MainActor.run { previewImage = UIImage(cgImage: cg) }
        }
    }

    private func updateVideoComposition() {
        guard let item = player?.currentItem else { return }
        item.videoComposition = MediaIO.makeVideoComposition(
            asset: item.asset, params: look.params, format: settings.config.format)
    }

    // MARK: Saving

    @MainActor
    private func save() async {
        let params = look.params
        let format = settings.config.format
        busy = true; progress = 0; status = nil
        defer { busy = false }
        do {
            if let data = originalPhoto {
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    try MediaIO.processPhoto(data: data, params: params, format: format)
                }.value
                try await MediaIO.savePhoto(jpeg)
                status = "Saved new photo to your library"
            } else if let url = videoURL {
                player?.pause()
                let out = try await MediaIO.exportVideo(url: url, params: params, format: format) { value in
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
