import AVFoundation
import CoreImage
import UIKit

/// Live capture: every camera frame goes through FilmPipeline, then to the preview and (if recording) the file writer.
final class CameraService: NSObject, ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case photo = "PHOTO", video = "VIDEO"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .photo
    @Published var isRecording = false
    @Published var recordingSeconds = 0
    @Published var permissionDenied = false
    @Published var flashOn = false
    @Published var usingFront = false
    @Published var message: String?

    private var look: LookStore?
    weak var preview: MetalPreviewView?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "balutcam.session")
    private let outputQueue = DispatchQueue(label: "balutcam.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var configured = false

    private let frameLock = NSLock()
    private var latest: CIImage?
    private var drawPending = false

    // Touched only on outputQueue
    private var frameCount = 0
    private var wantsRecording = false
    private var writer: AVAssetWriter?
    private var writerVideo: AVAssetWriterInput?
    private var writerAudio: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false

    private var timer: Timer?

    func bind(_ look: LookStore) { self.look = look }

    // MARK: Session lifecycle

    func start() {
        Task {
            let video = await AVCaptureDevice.requestAccess(for: .video)
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { self.permissionDenied = !video }
            guard video else { return }
            let front = await MainActor.run { self.usingFront }
            sessionQueue.async {
                if !self.configured {
                    self.configureSession(front: front)
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func device(front: Bool) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
    }

    private func configureSession(front: Bool) {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let dev = device(front: front),
           let input = try? AVCaptureDeviceInput(device: dev),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            audioOutput.setSampleBufferDelegate(self, queue: outputQueue)
            if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }
        session.commitConfiguration()
        applyConnectionSettings(front: front)
    }

    private func applyConnectionSettings(front: Bool) {
        for conn in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)].compactMap({ $0 }) {
            if #available(iOS 17.0, *) {
                if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            } else if conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
        if let c = videoOutput.connection(with: .video), c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = front
        }
    }

    func flipCamera() {
        guard !isRecording else { return }
        usingFront.toggle()
        let front = usingFront
        sessionQueue.async {
            guard let dev = self.device(front: front),
                  let newInput = try? AVCaptureDeviceInput(device: dev) else { return }
            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
            }
            self.session.commitConfiguration()
            self.applyConnectionSettings(front: front)
        }
    }

    // MARK: Preview frames

    func currentFrame() -> CIImage? {
        frameLock.lock(); defer { frameLock.unlock() }
        return latest
    }

    private func publish(_ image: CIImage) {
        frameLock.lock()
        latest = image
        let kick = !drawPending
        drawPending = true
        frameLock.unlock()
        guard kick else { return }
        DispatchQueue.main.async {
            self.frameLock.lock(); self.drawPending = false; self.frameLock.unlock()
            self.preview?.setNeedsDisplay()
        }
    }

    // MARK: Photo

    func capturePhoto() {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.isHighResolutionPhotoEnabled = true
        if photoOutput.supportedFlashModes.contains(.on) {
            settings.flashMode = flashOn ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: Video

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        recordingSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingSeconds += 1
        }
        setTorch(flashOn && !usingFront)
        outputQueue.async { self.wantsRecording = true }
    }

    private func stopRecording() {
        isRecording = false
        timer?.invalidate(); timer = nil
        setTorch(false)
        outputQueue.async { self.finishRecording() }
    }

    private func setTorch(_ on: Bool) {
        sessionQueue.async {
            guard let dev = self.videoInput?.device, dev.hasTorch else { return }
            try? dev.lockForConfiguration()
            dev.torchMode = on ? .on : .off
            dev.unlockForConfiguration()
        }
    }

    private func beginWriter(width: Int, height: Int) {
        let w = width & ~1, h = height & ~1
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("balutcam-\(UUID().uuidString).mov")
        guard let wr = try? AVAssetWriter(url: url, fileType: .mov) else {
            wantsRecording = false
            toast("Could not start recording")
            return
        }
        let vSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 6]
        ]
        let vin = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vin.expectsMediaDataInRealTime = true
        let ad = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vin,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h
            ])
        if wr.canAdd(vin) { wr.add(vin) }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            let aSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000
            ]
            let ain = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            ain.expectsMediaDataInRealTime = true
            if wr.canAdd(ain) { wr.add(ain); writerAudio = ain }
        }
        writer = wr
        writerVideo = vin
        adaptor = ad
        sessionStarted = false
    }

    private func appendVideo(_ image: CIImage, time: CMTime) {
        if writer == nil {
            guard wantsRecording else { return }
            beginWriter(width: Int(image.extent.width), height: Int(image.extent.height))
        }
        guard let wr = writer, let vin = writerVideo, let ad = adaptor else { return }
        if !sessionStarted {
            guard wr.startWriting() else {
                wantsRecording = false
                toast("Recording failed: \(wr.error?.localizedDescription ?? "unknown")")
                resetWriter()
                return
            }
            wr.startSession(atSourceTime: time)
            sessionStarted = true
        }
        guard wr.status == .writing, vin.isReadyForMoreMediaData, let pool = ad.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        let pipeline = FilmPipeline.shared
        pipeline.context.render(image, to: buffer, bounds: image.extent, colorSpace: pipeline.colorSpace)
        ad.append(buffer, withPresentationTime: time)
    }

    private func appendAudio(_ sample: CMSampleBuffer) {
        guard sessionStarted, let wr = writer, wr.status == .writing,
              let ain = writerAudio, ain.isReadyForMoreMediaData else { return }
        ain.append(sample)
    }

    private func resetWriter() {
        writer = nil; writerVideo = nil; writerAudio = nil; adaptor = nil; sessionStarted = false
    }

    private func finishRecording() {
        wantsRecording = false
        guard let wr = writer else { return }
        let url = wr.outputURL
        let started = sessionStarted
        let vin = writerVideo, ain = writerAudio
        resetWriter()
        guard started, wr.status == .writing else {
            wr.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return
        }
        vin?.markAsFinished()
        ain?.markAsFinished()
        wr.finishWriting {
            Task.detached {
                do {
                    try await MediaIO.saveVideo(url)
                    self.toast("Video saved")
                } catch {
                    self.toast(error.localizedDescription)
                }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func toast(_ text: String) {
        DispatchQueue.main.async {
            self.message = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.message == text { self.message = nil }
            }
        }
    }
}

// MARK: - Delegates

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioOutput {
            appendAudio(sampleBuffer)
            return
        }
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCount &+= 1
        let params = look?.snapshot ?? .neutral
        let graded = FilmPipeline.shared.apply(CIImage(cvPixelBuffer: pixels), params: params, seed: frameCount)
        publish(graded)
        if wantsRecording || writer != nil {
            appendVideo(graded, time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            toast("Capture failed")
            return
        }
        let params = look?.snapshot ?? .neutral
        Task.detached(priority: .userInitiated) {
            do {
                let jpeg = try MediaIO.processPhoto(data: data, params: params)
                try await MediaIO.savePhoto(jpeg)
                self.toast("Photo saved")
            } catch {
                self.toast(error.localizedDescription)
            }
        }
    }
}
