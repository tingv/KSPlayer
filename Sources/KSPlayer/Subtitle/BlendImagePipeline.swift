import CoreGraphics
import libass
import simd

/// Pipeline that processed an `ASS_Image` into a ``ProcessedImage``
/// by alpha blending in place all the layers one by one.
public final class BlendImagePipeline: ImagePipelineType {
    public static func process(images: [ASS_Image], boundingRect: CGRect) -> CGImage? {
        let (rgbData, linesize) = renderBlend(images: images, boundingRect: boundingRect)
        let image = CGImage.make(rgbData: rgbData, linesize: linesize, width: Int(boundingRect.size.width), height: Int(boundingRect.size.height), isAlpha: true)
        rgbData.deallocate()
        return image
    }

    private static func renderBlend(images: [ASS_Image], boundingRect: CGRect) -> (UnsafeMutablePointer<UInt8>, Int) {
        let width = Int(boundingRect.width)
        let height = Int(boundingRect.height)
        let bufferCapacity = width * height
        let buffer = UnsafeMutablePointer<SIMD4<Float>>.allocate(capacity: bufferCapacity)
        buffer.initialize(repeating: SIMD4<Float>.zero, count: bufferCapacity)
        loop(iterations: images.count) { i in
            let image = images[i]
            let stride = Int(image.stride)
            let red = Float((image.color >> 24) & 0xFF)
            let green = Float((image.color >> 16) & 0xFF)
            let blue = Float((image.color >> 8) & 0xFF)
            let normalizedAlpha = Float(255 - UInt8(image.color & 0xFF)) / 255.0
            let color = SIMD4<Float>(red, green, blue, 1)
            var bitmapPosition = 0
            var vImagePosition = (Int(image.dst_y) - Int(boundingRect.origin.y)) * width + Int(image.dst_x) - Int(boundingRect.origin.x)
            loop(iterations: Int(image.h)) { _ in
                loop(iterations: Int(image.w)) { x in
                    var alpha = normalizedAlpha * Float(image.bitmap[bitmapPosition + x]) / 255.0
                    // 在debug用*4 反而比<<2 更快。release就不会了
                    let index = vImagePosition + x
                    // 在debug用SIMD4<Float>反而更慢。release就不会了。
                    buffer[index] += (color - buffer[index]) * alpha
                }
                bitmapPosition += stride
                vImagePosition += width
            }
        }
        let result = UnsafeMutablePointer<SIMD4<UInt8>>.allocate(capacity: bufferCapacity)
        result.initialize(repeating: SIMD4<UInt8>.zero, count: bufferCapacity)
        loop(iterations: bufferCapacity) { index in
            let alpha = buffer[index].w
            if alpha >= 1 / 255.0 {
                result[index] = SIMD4<UInt8>(min(buffer[index] / SIMD4<Float>(alpha, alpha, alpha, 1 / 255.0), 255.0))
            }
        }
        buffer.deallocate()
        let pointer = result.withMemoryRebound(to: UInt8.self, capacity: bufferCapacity * 4) { pointer in
            pointer
        }
        return (pointer, width * 4)
    }
}
