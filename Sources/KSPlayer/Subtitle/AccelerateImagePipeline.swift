import Accelerate
import CoreGraphics
import libass
import QuartzCore

/// Pipeline that processed an `ASS_Image` into a ``ProcessedImage``
/// by combining all images using `vImage.PixelBuffer`.
@available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *)
public final class AccelerateImagePipeline: ImagePipelineType {
    public static func process(images: [ASS_Image], boundingRect: CGRect) -> CGImage? {
        let buffers = images.lazy.compactMap { translateBuffer($0, boundingRect: boundingRect) }
        let destinationBuffer = buffers[0]
        for buffer in buffers.dropFirst() {
            destinationBuffer.alphaComposite(
                .nonpremultiplied,
                topLayer: buffer,
                destination: destinationBuffer
            )
        }
        return makeImage(from: destinationBuffer, alphaInfo: .first)
    }

    private static func translateBuffer(_ image: ASS_Image, boundingRect: CGRect) -> vImage.PixelBuffer<vImage.Interleaved8x4>? {
        let width = Int(image.w)
        let height = Int(image.h)
        guard let size = vImage.Size(exactly: boundingRect.size) else { return nil }
        let destinationBuffer = makePixelBuffer(size: size, fillColor: (0, 0, 0, 0))
        let relativeRect = image.imageRect.relativeRect(to: boundingRect)
        let stride = Int(image.stride)
        let red = UInt8((image.color >> 24) & 0xFF)
        let green = UInt8((image.color >> 16) & 0xFF)
        let blue = UInt8((image.color >> 8) & 0xFF)
        var bitmapPosition = 0
        let rowBytes = destinationBuffer.rowStride * destinationBuffer.byteCountPerPixel
        var vImagePosition = Int(relativeRect.minY) * rowBytes
        destinationBuffer.withUnsafeMutableBufferPointer { bufferPtr in
            loop(iterations: height) { _ in
                loop(iterations: width) { x in
                    let alpha = image.bitmap[bitmapPosition + x]
                    if alpha == 0 {
                        return
                    }
                    let index = vImagePosition + (x + Int(relativeRect.minX)) * destinationBuffer.channelCount
                    bufferPtr[index + 0] = alpha
                    bufferPtr[index + 1] = red
                    bufferPtr[index + 2] = green
                    bufferPtr[index + 3] = blue
                }
                vImagePosition += rowBytes
                bitmapPosition += stride
            }
        }
        return destinationBuffer
    }

    private static func makePixelBuffer(size: vImage.Size, fillColor: Pixel_8888) -> vImage.PixelBuffer<vImage.Interleaved8x4> {
        let destinationBuffer = vImage.PixelBuffer(
            size: size,
            pixelFormat: vImage.Interleaved8x4.self
        )
        destinationBuffer.overwriteChannels(
            [0, 1, 2, 3],
            withPixel: fillColor,
            destination: destinationBuffer
        )

        return destinationBuffer
    }

    private static func makeImage(from buffer: vImage.PixelBuffer<vImage.Interleaved8x4>, alphaInfo: CGImageAlphaInfo) -> CGImage? {
        vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8 * 4,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue)
        ).flatMap { format in
            buffer.makeCGImage(cgImageFormat: format)
        }
    }
}

extension ASS_Image {
    var imageRect: CGRect {
        let origin = CGPoint(x: Int(dst_x), y: Int(dst_y))
        let size = CGSize(width: Int(w), height: Int(h))

        return CGRect(origin: origin, size: size)
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
