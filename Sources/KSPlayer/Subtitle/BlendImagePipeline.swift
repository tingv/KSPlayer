import Accelerate
import CoreGraphics
import libass

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
        let rowBytes = width << 2
        let bufferCapacity = rowBytes * height
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: bufferCapacity)
        buffer.initialize(repeating: 0, count: bufferCapacity)
        loop(iterations: images.count) { i in
            let image = images[i]
            /// 因为对于复杂的ass字幕的话，耗时会很高。超过0.1的话，就会感受到字幕延迟，体验不好。
            /// 所以先过滤掉一部分的ass特效。如果这个算法后续可以优化的话，那可以放开这个特殊的过滤逻辑
            if images.count > 5000, image.w <= 50, image.h <= 50 {
                return
            }
            let stride = Int(image.stride)
            let red = Float((image.color >> 24) & 0xFF)
            let green = Float((image.color >> 16) & 0xFF)
            let blue = Float((image.color >> 8) & 0xFF)
            var bitmapPosition = 0
            var vImagePosition = (Int(image.dst_y) - Int(boundingRect.origin.y)) * rowBytes + (Int(image.dst_x) - Int(boundingRect.origin.x)) * 4
            loop(iterations: Int(image.h)) { _ in
                loop(iterations: Int(image.w)) { x in
                    let alpha = Float(image.bitmap[bitmapPosition + x]) / 255.0
                    // 用*4 反而比<<2 更快。无法理解
                    let index = vImagePosition + x * 4
                    // 用vDSP和SIMD4<Float>反而更慢。无法理解
                    // 乘法运算float比Int会更快
//                    var tmpVector = [Float](repeating: 0.0, count: 4)
//                    vDSP_vsub(buffer.advanced(by: index), 1, colorVector, 1, &tmpVector, 1, 4)
//                    vDSP_vsmul(tmpVector, 1, &alpha, &tmpVector, 1, 4)
//                    vDSP_vadd(tmpVector, 1, buffer.advanced(by: index), 1, buffer.advanced(by: index), 1, 4)
                    buffer[index] += (red - buffer[index]) * alpha
                    buffer[index + 1] += (green - buffer[index + 1]) * alpha
                    buffer[index + 2] += (blue - buffer[index + 2]) * alpha
                    buffer[index + 3] += (1 - buffer[index + 3]) * alpha
                }
                bitmapPosition += stride
                vImagePosition += rowBytes
            }
        }
        let result = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferCapacity)
        result.initialize(repeating: 0, count: bufferCapacity)
        var position = 0
        loop(iterations: height) { _ in
            loop(iterations: width) { x in
                let index = position + x * 4
                let alpha = buffer[index + 3]
                if alpha >= 1 / 255.0 {
                    result[index] = UInt8(buffer[index] / alpha)
                    result[index + 1] = UInt8(buffer[index + 1] / alpha)
                    result[index + 2] = UInt8(buffer[index + 2] / alpha)
                    if alpha < 1 {
                        result[index + 3] = UInt8(alpha * 255.0)
                    } else {
                        result[index + 3] = 255
                    }
                }
            }
            position += rowBytes
        }
        buffer.deallocate()
        return (result, rowBytes)
    }

//    @inlinable
//    public static func clamp(_ value: Float) -> UInt8 {
//        if value >= 1 / 255.0 {
//            if value < 1 {
//                return UInt8(value * 255.0)
//            } else {
//                return 255
//            }
//        } else {
//            return 0
//        }
//    }
}
