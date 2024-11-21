//
//  AssImageParse.swift
//
//
//  Created by kintan on 5/4/24.
//

import Accelerate
import Foundation
import libass
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public final class AssImageParse: KSParseProtocol {
    public func canParse(scanner: Scanner) -> Bool {
        if KSOptions.isSRTUseImageRender, scanner.string.contains(" --> ") {
            scanner.charactersToBeSkipped = nil
            scanner.scanString("WEBVTT")
            return true
        }
        if KSOptions.isASSUseImageRender, scanner.scanString("[Script Info]") != nil {
            return true
        }
        return false
    }

    public func parsePart(scanner _: Scanner) -> SubtitlePart? {
        nil
    }

    public func parse(scanner: Scanner) -> KSSubtitleProtocol {
        let content: String
        if scanner.string.contains(" --> ") {
            content = scanner.changeToAss()
        } else {
            content = scanner.string
        }
        return AssImageRenderer(content: content)
    }
}

public final actor AssImageRenderer {
    private let library: OpaquePointer?
    private let renderer: OpaquePointer?
    private var currentTrack: UnsafeMutablePointer<ASS_Track>?
    public init(content: String? = nil) {
        library = ass_library_init()
        renderer = ass_renderer_init(library)
        ass_set_extract_fonts(library, 1)
        // 这个是用内存来加载字体，如果字体多的话，会导致内存暴涨，用系统的方法还是无法加载字体，所以只能用这个方法来加载
        ass_set_fonts_dir(library, KSOptions.fontsDir.path)
        // 用FONTCONFIG会比较耗时，并且文字可能会大小不一致
        ass_set_fonts(renderer, KSOptions.defaultFont?.path, nil, Int32(ASS_FONTPROVIDER_AUTODETECT.rawValue), nil, 0)
        if let content, var buffer = content.cString(using: .utf8) {
            currentTrack = ass_read_memory(library, &buffer, buffer.count, nil)
        } else {
            currentTrack = ass_new_track(library)
        }
//        ass_set_selective_style_override_enabled(library, Int32(ASS_OVERRIDE_BIT_SELECTIVE_FONT_SCALE.rawValue))
//        var style = ASS_Style()
//        ass_set_selective_style_override(library, &style)
    }

    public func subtitle(header: String) {
        if var buffer = header.cString(using: .utf8) {
            ass_process_codec_private(currentTrack, &buffer, Int32(buffer.count))
        }
    }

    public func add(subtitle: String, start: Int64, duration: Int64) {
        if var buffer = subtitle.cString(using: .utf8) {
            ass_process_chunk(currentTrack, &buffer, Int32(buffer.count), start, duration)
        }
    }

    public func setFrame(size: CGSize) {
        let width = Int32(size.width * KSOptions.scale)
        let height = Int32(size.height * KSOptions.scale)
        ass_set_frame_size(renderer, width, height)
        ass_set_storage_size(renderer, width, height)
    }

    public func flush() {
        ass_flush_events(currentTrack)
    }

    deinit {
        ass_free_track(currentTrack)
        ass_library_done(library)
        ass_renderer_done(renderer)
    }
}

extension AssImageRenderer: KSSubtitleProtocol {
    public func image(for time: TimeInterval, changed: inout Int32, isHDR: Bool) -> (CGRect, CGImage)? {
        let millisecond = Int64(time * 1000)
//        let start = CACurrentMediaTime()
        guard let frame = ass_render_frame(renderer, currentTrack, millisecond, &changed) else {
            return nil
        }
        guard changed != 0 else {
            return nil
        }
        let images = frame.pointee.linkedImages()
        let boundingRect = images.map(\.imageRect).boundingRect()
        let imagePipeline: ImagePipelineType.Type
        /// 如果图片大于10张的话，那要用PointerImagePipeline。
        /// 图片小的话，用PointerImagePipeline 差不多是0.0001，而Accelerate要0.0003。
        /// 图片大的话  用Accelerate差不多0.005 ，而PointerImagePipeline差不多要0.04
        if images.count <= 10, #available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, macCatalyst 16.0, *) {
            imagePipeline = vImage.PixelBuffer<vImage.Interleaved8x4>.self
        } else {
            imagePipeline = PointerImagePipeline.self
        }
        guard let image = imagePipeline.process(images: images, boundingRect: boundingRect, isHDR: isHDR) else {
            return nil
        }
//        print("image count: \(images.count) time:\(CACurrentMediaTime() - start)")
        return (boundingRect, image)
    }

    public func search(for time: TimeInterval, size: CGSize, isHDR: Bool) async -> [SubtitlePart] {
        setFrame(size: size)
        var changed = Int32(0)
        guard let processedImage = image(for: time, changed: &changed, isHDR: isHDR) else {
            if changed == 0 {
                return []
            } else {
                return [SubtitlePart(time, .infinity, "")]
            }
        }
        let rect = (processedImage.0 / KSOptions.scale).integral
        let info = SubtitleImageInfo(rect: rect, image: UIImage(cgImage: processedImage.1), displaySize: size)
        let part = SubtitlePart(time, .infinity, image: info)
        return [part]
    }
}

/// Pipeline that processed an `ASS_Image` into a ``ProcessedImage`` that can be drawn on the screen.
public protocol ImagePipelineType {
    init(images: [ASS_Image], boundingRect: CGRect)
    init(width: Int, height: Int, stride: Int, bitmap: UnsafePointer<UInt8>, palette: UnsafePointer<UInt32>)
    func cgImage(isHDR: Bool, alphaInfo: CGImageAlphaInfo) -> CGImage?
}

public extension ImagePipelineType {
    static func process(images: [ASS_Image], boundingRect: CGRect, isHDR: Bool) -> CGImage? {
        Self(images: images, boundingRect: boundingRect).cgImage(isHDR: isHDR, alphaInfo: .first)
    }
}
