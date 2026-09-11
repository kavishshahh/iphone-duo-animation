import AppKit
import MetalKit
import SwiftUI
import FoldCore

enum AppResources {
    static var bundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("Still_Still.bundle")) { return bundle }
        return Bundle.module
    }
    static func url(_ name: String, extension ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
            ?? bundle.url(forResource: name, withExtension: ext)
    }
    static var demoImage: CGImage? = {
        guard let url = url("wallpaper", extension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        let canvas = NSImage(size: NSSize(width: 1600, height: 1000))
        canvas.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1000))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let white = NSColor.white.withAlphaComponent(0.9)
        ("A moment of Still" as NSString).draw(in: NSRect(x: 0, y: 825, width: 1600, height: 44),
            withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: white, .paragraphStyle: centered])
        ("9:41" as NSString).draw(in: NSRect(x: 0, y: 660, width: 1600, height: 160),
            withAttributes: [.font: NSFont.systemFont(ofSize: 140, weight: .semibold), .foregroundColor: white, .paragraphStyle: centered])
        canvas.unlockFocus()
        return canvas.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()
}

private struct FoldUniforms {
    var angle: Float
    var workingAngle: Float
    var perspective: Float
    var frost: Float
    var shade: Float
    var fadeAngle: Float
    var aspect: Float
    var padding: Float = 0
}

final class FoldSurface: MTKView {
    private var foldRenderer: FoldRenderer?
    private(set) var setupError: String?
    private var imageIdentity: CGImage?

    init() {
        let gpu = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: gpu)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        isPaused = true
        enableSetNeedsDisplay = true
        framebufferOnly = true
        autoResizeDrawable = true
        do {
            guard let gpu else { throw NSError(domain: "Still", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal is not available on this Mac."]) }
            foldRenderer = try FoldRenderer(device: gpu, format: colorPixelFormat)
            delegate = foldRenderer
        } catch { setupError = error.localizedDescription }
    }
    required init(coder: NSCoder) { fatalError("Use init()") }

    func update(image: CGImage?, angle: Double, tuning: FoldTuning) {
        if imageIdentity !== image {
            imageIdentity = image
            do { try foldRenderer?.setImage(image) }
            catch { setupError = error.localizedDescription }
        }
        foldRenderer?.angle = angle
        foldRenderer?.tuning = tuning.validated
        needsDisplay = true
    }

    func clearSnapshot() {
        imageIdentity = nil
        try? foldRenderer?.setImage(nil)
        needsDisplay = true
    }
}

private final class FoldRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var texture: MTLTexture?
    var angle: Double = 105
    var tuning = FoldTuning()

    init(device: MTLDevice, format: MTLPixelFormat) throws {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let url = AppResources.url("Fold", extension: "metal") else {
            throw NSError(domain: "Still", code: 2, userInfo: [NSLocalizedDescriptionKey: "Animation resources are missing. Rebuild the app bundle."])
        }
        self.queue = queue
        let source = try String(contentsOf: url, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    func setImage(_ image: CGImage?) throws {
        texture = nil
        guard let image else { return }
        texture = try MTKTextureLoader(device: device).newTexture(cgImage: image, options: [
            .SRGB: false, .generateMipmaps: true, .origin: MTKTextureLoader.Origin.topLeft
        ])
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let texture {
            var uniforms = FoldUniforms(angle: Float(angle), workingAngle: Float(tuning.workingAngle),
                perspective: Float(tuning.perspective), frost: Float(tuning.frost), shade: Float(tuning.shade),
                fadeAngle: Float(tuning.fadeAngle), aspect: Float(texture.width) / Float(texture.height))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }
}

struct MetalPreview: NSViewRepresentable {
    let angle: Double
    let tuning: FoldTuning
    func makeNSView(context: Context) -> FoldSurface { FoldSurface() }
    func updateNSView(_ view: FoldSurface, context: Context) {
        view.update(image: AppResources.demoImage, angle: angle, tuning: tuning)
    }
}
