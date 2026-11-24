import CoreGraphics
import simd
import UIKit

@_silgen_name("plate_raster")
private func plateRaster(
    _ dst: UnsafeMutablePointer<UInt8>,
    _ width: Int32,
    _ height: Int32,
    _ cushion: UnsafePointer<UInt8>?,
    _ cushionW: Int32,
    _ cushionH: Int32,
    _ cat: UnsafePointer<UInt8>?,
    _ catW: Int32,
    _ catH: Int32,
    _ mask: UnsafePointer<UInt8>?,
    _ maskW: Int32,
    _ maskH: Int32,
    _ flowX: UnsafePointer<Float>?,
    _ flowY: UnsafePointer<Float>?,
    _ part: UnsafePointer<Float>?,
    _ groomW: Int32,
    _ groomH: Int32,
    _ ox: Float,
    _ oy: Float,
    _ dw: Float,
    _ dh: Float,
    _ breath: Float,
    _ earL: Float,
    _ earR: Float,
    _ chubScale: Float,
    _ stretch: Float,
    _ sway: Float,
    _ night: Int32,
    _ rain: Int32,
    _ time: Float,
    _ drawCat: Int32
)

enum ScenePainter {
    static func render(
        bounds: CGSize,
        scale: CGFloat,
        coat: Coat,
        scene: RoomScene,
        pose: CatPose,
        groom: GroomField,
        rain: Float,
        time: Float,
        catSize: Float,
        interactive: Bool,
        drawCat: Bool = true
    ) -> UIImage {
        var pixelScale = max(scale, 1)
        var width = max(1, Int((bounds.width * pixelScale).rounded()))
        var height = max(1, Int((bounds.height * pixelScale).rounded()))
        let cap = interactive ? 900 : 1600
        let longSide = max(width, height)
        if longSide > cap {
            let fit = Double(cap) / Double(longSide)
            width = max(1, Int((Double(width) * fit).rounded()))
            height = max(1, Int((Double(height) * fit).rounded()))
            pixelScale = bounds.height > 1 ? CGFloat(height) / bounds.height : pixelScale
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let library = PlateLibrary.shared
        let cushion = library.cushion
        let cat = drawCat ? library.cat(coat) : cushion
        let mask = drawCat ? library.mask(coat) : PlateImage(width: 1, height: 1, rgba: [0, 0, 0, 255])
        let maps = groom.packed()
        let placed = CatLayout.fitRect(in: CGSize(width: width, height: height), catSize: catSize)
        let dw = Float(placed.width)
        let dh = Float(placed.height)
        let ox = Float(placed.minX)
        let oy = Float(placed.minY)
        let chubScale = 0.96 + pose.chub * 0.08

        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            cushion.rgba.withUnsafeBufferPointer { cushionPx in
                cat.rgba.withUnsafeBufferPointer { catPx in
                    mask.rgba.withUnsafeBufferPointer { maskPx in
                        maps.flowX.withUnsafeBufferPointer { fx in
                            maps.flowY.withUnsafeBufferPointer { fy in
                                maps.part.withUnsafeBufferPointer { part in
                                    plateRaster(
                                        base, Int32(width), Int32(height),
                                        cushionPx.baseAddress, Int32(cushion.width), Int32(cushion.height),
                                        catPx.baseAddress, Int32(cat.width), Int32(cat.height),
                                        maskPx.baseAddress, Int32(mask.width), Int32(mask.height),
                                        fx.baseAddress, fy.baseAddress, part.baseAddress,
                                        Int32(maps.width), Int32(maps.height),
                                        ox, oy, dw, dh,
                                        pose.breath, pose.earL, pose.earR, chubScale,
                                        pose.tailStretch, pose.tailSway,
                                        scene == .night ? 1 : 0,
                                        rain > 0.5 ? 1 : 0,
                                        time,
                                        drawCat ? 1 : 0
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else {
            return UIImage()
        }
        return UIImage(cgImage: image, scale: pixelScale, orientation: .up)
    }
}
