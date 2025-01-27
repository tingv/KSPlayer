import CoreGraphics
import libass
import simd

public final class PointerImagePipeline: ImagePipelineType {
    private let rgbData: UnsafeMutablePointer<UInt8>
    private let stride: Int
    private let width: Int
    private let height: Int
    public init(rgbData: UnsafeMutablePointer<UInt8>, stride: Int, width: Int, height: Int) {
        self.rgbData = rgbData
        self.stride = stride
        self.width = width
        self.height = height
    }

    public init(width: Int, height: Int, stride: Int, bitmap: UnsafeMutablePointer<UInt8>, palette: UnsafePointer<UInt32>) {
        self.width = width
        self.height = height
        self.stride = stride
        let bufferCapacity = stride * height
        let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: bufferCapacity)
        buffer.initialize(repeating: 0, count: bufferCapacity)
        var bitmapPosition = 0
        loop(iterations: height) { _ in
            loop(iterations: width) { x in
                buffer[bitmapPosition + x] = palette[Int(bitmap[bitmapPosition + x])]
            }
            bitmapPosition += stride
        }
        rgbData = buffer.withMemoryRebound(to: UInt8.self, capacity: bufferCapacity * 4) { $0 }
    }

    /// Pipeline that processed an `ASS_Image` into a ``ImagePipeline``
    /// by alpha blending in place all the layers one by one.
    ///
    public init(images: [ASS_Image], boundingRect: CGRect) {
        let width = Int(boundingRect.width)
        height = Int(boundingRect.height)
        self.width = width
        self.stride = width
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
            let color = SIMD4<Float>(1, red, green, blue)
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
            let alpha = buffer[index].x
            if alpha >= 1 / 255.0 {
                result[index] = SIMD4<UInt8>(min(buffer[index] / SIMD4<Float>(1 / 255.0, alpha, alpha, alpha), 255.0))
            }
        }
        buffer.deallocate()
        rgbData = result.withMemoryRebound(to: UInt8.self, capacity: bufferCapacity * 4) { $0 }
    }

    public func cgImage(isHDR: Bool, alphaInfo: CGImageAlphaInfo) -> CGImage? {
        defer {
            rgbData.deallocate()
        }
        let colorSpace = isHDR ? KSOptions.colorSpace2020PQ ?? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: alphaInfo.rawValue)
        let bitsPerPixel = alphaInfo != .none ? 32 : 24
        let bytesPerRow = stride * bitsPerPixel / 8
        guard let data = CFDataCreate(kCFAllocatorDefault, rgbData, bytesPerRow * height), let provider = CGDataProvider(data: data) else {
            return nil
        }
        // swiftlint:disable line_length
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        // swiftlint:enable line_length
    }
}
