import MetalKit
import SwiftUI
import UIKit

enum RendererChoice {
    static var useMetal: Bool {
        if DemoShot.forceCPU { return false }
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              library.makeFunction(name: "purrVertex") != nil,
              library.makeFunction(name: "purrFragment") != nil else { return false }
        return true
    }
}

struct CatCanvas: UIViewRepresentable {
    let session: PetSession
    let settings: AppSettings

    func makeUIView(context: Context) -> UIView {
        if RendererChoice.useMetal, let device = MTLCreateSystemDefaultDevice() {
            return MetalCatView(session: session, settings: settings, device: device)
        }
        return CPUCatView(session: session, settings: settings)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let cpu = uiView as? CPUCatView {
            cpu.note(settings)
        } else if let metal = uiView as? MetalCatView {
            metal.settings = settings
        }
    }
}

final class CPUCatView: UIView {
    let session: PetSession
    var settings: AppSettings
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var didFinishStill = false
    private var painting = false
    private var renderingCat = false

    func note(_ settings: AppSettings) {
        let changed = self.settings.coat != settings.coat || self.settings.scene != settings.scene || self.settings.rain != settings.rain || self.settings.handEnabled != settings.handEnabled
        self.settings = settings
        if changed {
            didFinishStill = false
            accessibilityIdentifier = "shot-pending"
            setNeedsLayout()
        }
    }

    init(session: PetSession, settings: AppSettings) {
        self.session = session
        self.settings = settings
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = UIColor(red: 0.83, green: 0.78, blue: 0.70, alpha: 1)
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Stroke the cat")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, !DemoShot.underTest, session.isFrozen else { return }
        paintStill()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil, !DemoShot.underTest else { return }
        if session.isFrozen {
            paintStill()
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    deinit { link?.invalidate() }

    @objc private func step(_ link: CADisplayLink) {
        guard !session.isFrozen else { return }
        let dt = last == 0 ? (1.0 / 30.0) : (link.timestamp - last)
        last = link.timestamp
        session.tick(dt: dt, bounds: bounds.size, settings: settings)
        renderFrame(interactive: true)
    }

    /// Starts the frozen frame off the main thread and marks the view ready only once that frame is on screen.
    private func paintStill() {
        guard bounds.width > 2, bounds.height > 2, !didFinishStill, !painting else { return }
        painting = true
        if settings.handEnabled, session.handAnchor == nil {
            session.placeDemoHand(in: bounds.size, settings: settings)
        }
        let boundsSize = bounds.size
        let scale = min(window?.screen.scale ?? 2, 2)
        let coat = settings.coat
        let scene = settings.scene
        let pose = session.pose
        let groom = session.groom.snapshot()
        let rain: Float = settings.rain ? 1 : 0
        let time = Float(session.time)
        let catSize = settings.catSize
        backgroundColor = scene == .night
            ? UIColor(red: 0.16, green: 0.22, blue: 0.32, alpha: 1)
            : UIColor(red: 0.83, green: 0.78, blue: 0.70, alpha: 1)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ScenePainter.render(
                bounds: boundsSize, scale: scale, coat: coat, scene: scene, pose: pose,
                groom: groom, rain: rain, time: time, catSize: catSize,
                interactive: false, drawCat: true
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.painting = false
                guard self.settings.coat == coat, self.settings.scene == scene else {
                    self.paintStill()
                    return
                }
                self.layer.contentsScale = image.scale
                self.layer.contents = image.cgImage
                guard self.matchesDemo else { return }
                self.didFinishStill = true
                self.accessibilityIdentifier = "shot-ready"
            }
        }
    }

    private func renderFrame(interactive: Bool) {
        guard bounds.width > 2, bounds.height > 2, !renderingCat else { return }
        let boundsSize = bounds.size
        let scale = min(window?.screen.scale ?? 2, 1)
        let coat = settings.coat
        let scene = settings.scene
        let pose = session.pose
        let groom = session.groom.snapshot()
        let rain: Float = settings.rain ? 1 : 0
        let time = Float(session.time)
        let catSize = settings.catSize
        renderingCat = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ScenePainter.render(
                bounds: boundsSize, scale: scale, coat: coat, scene: scene, pose: pose,
                groom: groom, rain: rain, time: time, catSize: catSize,
                interactive: interactive, drawCat: true
            )
            DispatchQueue.main.async {
                guard let self else { return }
                self.layer.contentsScale = image.scale
                self.layer.contents = image.cgImage
                self.renderingCat = false
            }
        }
    }

    private var matchesDemo: Bool {
        guard let shot = DemoShot.current else { return false }
        switch shot {
        case .day:
            return settings.scene == .day && settings.coat == .black && settings.handEnabled && session.handAnchor != nil
        case .night:
            return settings.scene == .night && settings.coat == .black
        case .coats:
            return settings.scene == .day && settings.coat == .calico
        case .paywall:
            return settings.coat == .ginger
        case .stroke:
            return false
        }
    }
}

final class MetalCatView: MTKView, MTKViewDelegate {
    let session: PetSession
    var settings: AppSettings
    private var pipeline: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private var groomTexture: MTLTexture?
    private var cushionTexture: MTLTexture?
    private var catTextures: [Int: MTLTexture] = [:]
    private var maskTextures: [Int: MTLTexture] = [:]
    private var last: CFTimeInterval = 0

    init(session: PetSession, settings: AppSettings, device: MTLDevice) {
        self.session = session
        self.settings = settings
        super.init(frame: .zero, device: device)
        self.device = device
        delegate = self
        framebufferOnly = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 120
        colorPixelFormat = .bgra8Unorm
        isOpaque = true
        commandQueue = device.makeCommandQueue()
        if let library = device.makeDefaultLibrary(),
           let vertex = library.makeFunction(name: "purrVertex"),
           let fragment = library.makeFunction(name: "purrFragment") {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertex
            desc.fragmentFunction = fragment
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try? device.makeRenderPipelineState(descriptor: desc)
        }
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: session.groom.width, height: session.groom.height, mipmapped: false
        )
        td.usage = [.shaderRead]
        groomTexture = device.makeTexture(descriptor: td)
        let plates = PlateLibrary.shared
        cushionTexture = plates.cushion.makeTexture(device: device)
        for coat in Coat.allCases {
            catTextures[coat.rawValue] = plates.cat(coat).makeTexture(device: device)
            maskTextures[coat.rawValue] = plates.mask(coat).makeTexture(device: device)
        }
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Stroke the cat")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard bounds.width > 2,
              let pipeline,
              let commandQueue,
              let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let command = commandQueue.makeCommandBuffer(),
              let enc = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime()
        let dt = last == 0 ? (1.0 / 60.0) : (now - last)
        last = now
        session.tick(dt: dt, bounds: bounds.size, settings: settings)
        uploadGroom()
        var uniforms = CatUniforms.make(bounds: bounds.size, contentScale: max(contentScaleFactor, 1), settings: settings, session: session)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<CatUniforms>.stride, index: 0)
        enc.setFragmentTexture(groomTexture, index: 0)
        enc.setFragmentTexture(cushionTexture, index: 1)
        enc.setFragmentTexture(catTextures[settings.coat.rawValue] ?? cushionTexture, index: 2)
        enc.setFragmentTexture(maskTextures[settings.coat.rawValue], index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private func uploadGroom() {
        guard let groomTexture else { return }
        let bytes = session.groom.rgbaBytes()
        groomTexture.replace(
            region: MTLRegionMake2D(0, 0, groomTexture.width, groomTexture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: groomTexture.width * 4
        )
    }
}
