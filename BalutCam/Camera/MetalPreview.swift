import MetalKit
import SwiftUI
import CoreImage

/// Draws the already-graded CIImage straight to a Metal drawable (aspect-fit, black bars).
final class MetalPreviewView: MTKView {
    var frameProvider: (() -> CIImage?)?
    private let commandQueue: MTLCommandQueue

    init() {
        let dev = MTLCreateSystemDefaultDevice()!
        commandQueue = dev.makeCommandQueue()!
        super.init(frame: .zero, device: dev)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        colorPixelFormat = .bgra8Unorm
        backgroundColor = .black
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func draw(_ rect: CGRect) {
        guard let image = frameProvider?(),
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let size = drawableSize
        guard size.width > 0, size.height > 0, image.extent.width > 0, image.extent.height > 0 else { return }

        let scale = min(size.width / image.extent.width, size.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let tx = (size.width - scaled.extent.width) / 2 - scaled.extent.minX
        let ty = (size.height - scaled.extent.height) / 2 - scaled.extent.minY
        let placed = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        let bounds = CGRect(origin: .zero, size: size)
        let background = CIImage(color: .black).cropped(to: bounds)
        let composed = placed.composited(over: background)

        let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commandBuffer)
        destination.isFlipped = true
        destination.colorSpace = FilmPipeline.shared.colorSpace
        _ = try? FilmPipeline.shared.context.startTask(toRender: composed, to: destination)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct CameraPreview: UIViewRepresentable {
    let service: CameraService

    func makeUIView(context: Context) -> MetalPreviewView {
        let view = MetalPreviewView()
        view.frameProvider = { [weak service] in service?.currentFrame() }
        service.preview = view
        return view
    }

    func updateUIView(_ uiView: MetalPreviewView, context: Context) {}
}
