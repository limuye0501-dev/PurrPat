import CoreGraphics
import Metal
import simd
import UIKit

/// Decoded plate. Row 0 is the top of the photo, RGBA8.
struct PlateImage {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    func sample(_ u: Float, _ v: Float) -> SIMD4<Float> {
        if width < 2 || height < 2 || rgba.count < width * height * 4 {
            return SIMD4(0.8, 0.75, 0.68, 1)
        }
        let x = min(max(u, 0), 1) * Float(width - 1)
        let y = min(max(v, 0), 1) * Float(height - 1)
        let x0 = Int(x)
        let y0 = Int(y)
        let x1 = min(width - 1, x0 + 1)
        let y1 = min(height - 1, y0 + 1)
        let tx = x - Float(x0)
        let ty = y - Float(y0)
        let a = pixel(x0, y0)
        let b = pixel(x1, y0)
        let c = pixel(x0, y1)
        let d = pixel(x1, y1)
        let top = a * (1 - tx) + b * tx
        let bot = c * (1 - tx) + d * tx
        return top * (1 - ty) + bot * ty
    }

    private func pixel(_ x: Int, _ y: Int) -> SIMD4<Float> {
        let i = (y * width + x) * 4
        return SIMD4(
            Float(rgba[i]) / 255,
            Float(rgba[i + 1]) / 255,
            Float(rgba[i + 2]) / 255,
            Float(rgba[i + 3]) / 255
        )
    }

    func makeTexture(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: max(width, 1), height: max(height, 1), mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        rgba.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }
        return tex
    }
}

final class PlateLibrary {
    static let shared = PlateLibrary()

    let cushion: PlateImage
    private let cats: [Coat: PlateImage]
    private let masks: [Coat: PlateImage]
    private let swatches: [Coat: UIImage]

    func cat(_ coat: Coat) -> PlateImage { cats[coat] ?? cushion }
    func mask(_ coat: Coat) -> PlateImage { masks[coat] ?? PlateImage(width: 1, height: 1, rgba: [0, 0, 0, 255]) }
    func swatch(_ coat: Coat) -> UIImage { swatches[coat] ?? UIImage() }

    private init() {
        let bundle = Bundle(for: AppSettings.self)
        func load(_ name: String, _ ext: String) -> PlateImage? {
            guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
            guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
            return PlateImage.decode(image)
        }
        cushion = load("cushion", "jpg") ?? PlateImage.linen
        var cats: [Coat: PlateImage] = [:]
        var masks: [Coat: PlateImage] = [:]
        var swatches: [Coat: UIImage] = [:]
        for coat in Coat.allCases {
            cats[coat] = load("plate-\(coat.assetName)", "jpg") ?? cushion
            masks[coat] = load("mask-\(coat.assetName)", "png") ?? PlateImage(width: 1, height: 1, rgba: [255, 255, 255, 255])
            if let url = bundle.url(forResource: "swatch-\(coat.assetName)", withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                swatches[coat] = image
            }
        }
        self.cats = cats
        self.masks = masks
        self.swatches = swatches
    }
}

extension PlateImage {
    static func decode(_ image: CGImage) -> PlateImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let ok: Bool = rgba.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: info.rawValue
            ) else { return false }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return PlateImage(width: width, height: height, rgba: rgba)
    }

    static let linen = PlateImage(
        width: 2,
        height: 2,
        rgba: Array(repeating: [214, 198, 176, 255], count: 4).flatMap { $0 }
    )
}
