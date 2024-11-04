import Accelerate
import CoreGraphics
import libass
import QuartzCore

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *)
extension vImage.PixelBuffer<vImage.Interleaved8x4> {
    init(size: vImage.Size, fillColor: Pixel_8888) {
        self.init(size: size, pixelFormat: vImage.Interleaved8x4.self)
        overwriteChannels(
            [0, 1, 2, 3],
            withPixel: fillColor,
            destination: self
        )
    }

    init(width: Int, height: Int, stride: Int, color: UInt32, bitmap: UnsafePointer<UInt8>, relativePoint: CGPoint, size: CGSize) {
        self.init(size: vImage.Size(width: Int(size.width), height: Int(size.height)), fillColor: (0, 0, 0, 0))
        let red = UInt8((color >> 24) & 0xFF)
        let green = UInt8((color >> 16) & 0xFF)
        let blue = UInt8((color >> 8) & 0xFF)
        let normalizedAlpha = Float(255 - color & 0xFF) / 255.0
        var bitmapPosition = 0
        let rowBytes = rowStride * byteCountPerPixel
        var vImagePosition = Int(relativePoint.y) * rowBytes + Int(relativePoint.x) * channelCount
        withUnsafeMutableBufferPointer { bufferPtr in
            loop(iterations: height) { _ in
                loop(iterations: width) { x in
                    let alpha = UInt8(Float(bitmap[bitmapPosition + x]) * normalizedAlpha)
                    if alpha == 0 {
                        return
                    }
                    let index = vImagePosition + x * channelCount
                    bufferPtr[index + 0] = alpha
                    bufferPtr[index + 1] = red
                    bufferPtr[index + 2] = green
                    bufferPtr[index + 3] = blue
                }
                vImagePosition += rowBytes
                bitmapPosition += stride
            }
        }
    }

    public init(width: Int, height: Int, stride: Int, bitmap: UnsafePointer<UInt8>, palette: UnsafePointer<UInt32>) {
        let size = vImage.Size(width: width, height: height)
        self.init(size: size, pixelFormat: vImage.Interleaved8x4.self)
        var bitmapPosition = 0
        let rowBytes = rowStride
        var vImagePosition = 0
        withUnsafeMutableBufferPointer { bufferPtr in
            let bufferPtr = bufferPtr.withMemoryRebound(to: UInt32.self) { $0 }
            loop(iterations: height) { _ in
                loop(iterations: width) { x in
                    bufferPtr[vImagePosition + x] = palette[Int(bitmap[bitmapPosition + x])].bigEndian
                }
                vImagePosition += rowBytes
                bitmapPosition += stride
            }
        }
    }

    init(image: ASS_Image, boundingRect: CGRect) {
        self.init(width: Int(image.w), height: Int(image.h), stride: Int(image.stride), color: image.color, bitmap: image.bitmap, relativePoint: image.imageOrigin.relative(to: boundingRect.origin), size: boundingRect.size)
    }

    public func cgImage(isHDR: Bool, alphaInfo: CGImageAlphaInfo) -> CGImage? {
        vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8 * 4,
            colorSpace: isHDR ? KSOptions.colorSpace2020PQ ?? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue)
        ).flatMap { format in
            makeCGImage(cgImageFormat: format)
        }
    }
}

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *)
extension vImage.PixelBuffer<vImage.Interleaved8x4>: ImagePipelineType {
    public init(images: [ASS_Image], boundingRect: CGRect) {
        guard let first = images.first else {
            self.init(width: Int(boundingRect.width), height: Int(boundingRect.height))
            return
        }
        self.init(image: images[0], boundingRect: boundingRect)
        for image in images.dropFirst() {
            let buffer = Self(image: image, boundingRect: boundingRect)
            alphaComposite(
                .nonpremultiplied,
                topLayer: buffer,
                destination: self
            )
        }
    }
}

extension ASS_Image {
    var imageOrigin: CGPoint {
        CGPoint(x: Int(dst_x), y: Int(dst_y))
    }

    var imageRect: CGRect {
        let size = CGSize(width: Int(w), height: Int(h))
        return CGRect(origin: imageOrigin, size: size)
    }

    /// Find all the linked images from an `ASS_Image`.
    ///
    /// - Parameters:
    ///   - image: First image from the list.
    ///
    /// - Returns: A  list of `ASS_Image` that should be combined to produce
    /// a final image ready to be drawn on the screen.
    public func linkedImages() -> [ASS_Image] {
        var allImages: [ASS_Image] = []
        var currentImage: ASS_Image? = self
        while let image = currentImage {
            if image.w != 0, image.h != 0 {
                allImages.append(image)
            }
            currentImage = image.next?.pointee
        }
        return allImages
    }
}
