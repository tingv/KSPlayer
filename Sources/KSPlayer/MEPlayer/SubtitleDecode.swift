//
//  SubtitleDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

import Accelerate
import CoreGraphics
import Foundation
import Libavformat
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
class SubtitleDecode: DecodeProtocol {
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var subtitle = AVSubtitle()
    private var startTime = TimeInterval(0)
    private var assParse: AssParse? = nil
    private var assImageRenderer: AssIncrementImageRenderer? = nil
    private let isHDR: Bool
    private let isASS: Bool
    required init(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        startTime = assetTrack.startTime.seconds
        isHDR = KSOptions.enableHDRSubtitle ? options.dynamicRange.isHDR : false
        isASS = assetTrack.codecpar.codec_id == AV_CODEC_ID_SSA || assetTrack.codecpar.codec_id == AV_CODEC_ID_ASS || assetTrack.codecpar.codec_id == AV_CODEC_ID_EIA_608
        do {
            codecContext = try assetTrack.createContext(options: options)
            if let codecContext {
                if let pointer = codecContext.pointee.subtitle_header {
                    let subtitleHeader: String
                    if isASS {
                        subtitleHeader = String(cString: pointer)
                    } else {
                        let str = String(cString: pointer)
                        subtitleHeader = str
                            .replacingOccurrences(of: "PlayResY: 288", with: "PlayResY: 216")
                            .replacingOccurrences(of: "Style: Default,Arial,16,&Hffffff,&Hffffff,&H0,&H0,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1", with: KSOptions.assStyle)
                            // movtext的默认样式不一样
                            .replacingOccurrences(of: "Style: Default,Serif,18,&Hffffff,&Hffffff,&Hff000000,&Hff000000,0,0,0,0,100,100,0,0,1,1,0,2,10,10,10,1", with: KSOptions.assStyle)
                    }
                    // 所以文字字幕都会自动转为ass的格式，都会有subtitle_header。所以还要判断下字幕的类型
                    if (KSOptions.isASSUseImageRender && isASS) || KSOptions.isSRTUseImageRender {
                        assImageRenderer = AssIncrementImageRenderer(fontsDir: options.fontsDir?.path, header: subtitleHeader)
                        assetTrack.subtitleRender = assImageRenderer
                    } else {
                        let assParse = AssParse()
                        if assParse.canParse(scanner: Scanner(string: subtitleHeader)) {
                            self.assParse = assParse
                        }
                    }
                }
            }
        } catch {
            KSLog(error as CustomStringConvertible)
        }
    }

    func decode() {}

    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        guard let codecContext else {
            return
        }
        var gotsubtitle = Int32(0)
        _ = avcodec_decode_subtitle2(codecContext, &subtitle, &gotsubtitle, packet.corePacket)
        if gotsubtitle == 0 {
            return
        }
        let timestamp = packet.timestamp
        var start = packet.assetTrack.timebase.cmtime(for: timestamp).seconds + TimeInterval(subtitle.start_display_time) / 1000.0
        if start >= startTime {
            start -= startTime
        }
        var duration = 0.0
        if subtitle.end_display_time != UInt32.max {
            duration = TimeInterval(subtitle.end_display_time - subtitle.start_display_time) / 1000.0
        }
        if duration == 0, packet.duration != 0 {
            duration = packet.assetTrack.timebase.cmtime(for: packet.duration).seconds
        }
        let end: TimeInterval
        if duration == 0 {
            end = .infinity
        } else {
            end = start + duration
        }
        // init方法里面codecContext还没有宽高，需要等到这里才有。
        let displaySize = CGSize(width: Int(codecContext.pointee.width), height: Int(codecContext.pointee.height))
        var parts = text(subtitle: subtitle, start: start, end: end, displaySize: displaySize)
        /// 不用preSubtitleFrame来进行更新end。而是插入一个空的字幕来更新字幕。
        /// 因为字幕有可能不按顺序解码。这样就会导致end比start小，然后这个字幕就不会被清空了。
        if assImageRenderer == nil, parts.isEmpty {
            parts.append(SubtitlePart(start, end, ""))
        }
        for part in parts {
            let frame = SubtitleFrame(part: part, timebase: packet.assetTrack.timebase)
            frame.timestamp = timestamp
            completionHandler(.success(frame))
        }
        avsubtitle_free(&subtitle)
    }

    func doFlushCodec() {
        Task(priority: .high) {
            await assImageRenderer?.flush()
        }
    }

    func shutdown() {
        avsubtitle_free(&subtitle)
        if let codecContext {
            avcodec_free_context(&self.codecContext)
        }
    }

    private func text(subtitle: AVSubtitle, start: TimeInterval, end: TimeInterval, displaySize: CGSize) -> [SubtitlePart] {
        var parts = [SubtitlePart]()
        var images = [(CGRect, UIImage)]()
        var attributedString: NSMutableAttributedString?
        for i in 0 ..< Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee else {
                continue
            }
            if let text = rect.text {
                if attributedString == nil {
                    attributedString = NSMutableAttributedString()
                }
                attributedString?.append(NSAttributedString(string: String(cString: text)))
            } else if let ass = rect.ass {
                let subtitle = String(cString: ass)
                if let assImageRenderer {
                    Task(priority: .high) {
                        await assImageRenderer.add(subtitle: subtitle, start: Int64(start * 1000), duration: end == .infinity ? 1000 : Int64((end - start) * 1000))
                    }
                } else if let assParse {
                    let scanner = Scanner(string: subtitle)
                    if let group = assParse.parsePart(scanner: scanner) {
                        group.start = start
                        group.end = end
                        if !isASS, let string = group.text?.string {
                            if attributedString == nil {
                                attributedString = NSMutableAttributedString()
                            }
                            attributedString?.append(NSAttributedString(string: string))
                        } else {
                            parts.append(group)
                        }
                    }
                }
            } else if rect.type == SUBTITLE_BITMAP {
                if let bitmap = rect.data.0, let palette = rect.data.1 {
//                    let start = CACurrentMediaTime()
                    let image = PointerImagePipeline(
                        width: Int(rect.w),
                        height: Int(rect.h),
                        stride: Int(rect.linesize.0),
                        bitmap: bitmap,
                        palette: palette.withMemoryRebound(to: UInt32.self, capacity: Int(rect.nb_colors)) { $0 }
                    )
                    .cgImage(isHDR: isHDR, alphaInfo: .first).flatMap { UIImage(cgImage: $0) }
//                    print("image subtitle time:\(CACurrentMediaTime() - start)")
                    if let image {
                        let imageRect = CGRect(x: Int(rect.x), y: Int(rect.y), width: Int(rect.w), height: Int(rect.h))
                        images.append((imageRect, image))
                    }
                }
            }
        }
        if let attributedString {
            parts.append(SubtitlePart(start, end, attributedString: attributedString))
        }
        let boundingRect = images.map(\.0).boundingRect()
//        let displaySize = displaySize ?? CGSize(width: boundingRect.maxX + boundingRect.minX, height: boundingRect.maxY)
        // 不合并图片，有返回每个图片的rect，可以自己控制显示位置。
        for image in images {
            // 有些图片字幕不会带屏幕宽高，所以就取字幕自身的宽高。
            let info = SubtitleImageInfo(rect: image.0, image: image.1, displaySize: displaySize)
            let part = SubtitlePart(start, end, image: info)
            parts.append(part)
        }
        return parts
    }
}
