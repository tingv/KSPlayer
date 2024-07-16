//
//  SubtitleDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/11.
//

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
    private let scale = VideoSwresample(dstFormat: AV_PIX_FMT_ARGB, isDovi: false)
    private var subtitle = AVSubtitle()
    private var startTime = TimeInterval(0)
    private var assParse: AssParse? = nil
    private var assImageRenderer: AssImageRenderer? = nil
    private let displaySize: CGSize?
    required init(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        startTime = assetTrack.startTime.seconds
        displaySize = assetTrack.formatDescription?.displaySize
        do {
            codecContext = try assetTrack.createContext(options: options)
            if let codecContext, let pointer = codecContext.pointee.subtitle_header {
                let subtitleHeader = String(cString: pointer)
                if KSOptions.isASSUseImageRender {
                    assImageRenderer = AssImageRenderer()
                    assetTrack.sutitleRender = assImageRenderer
                    Task(priority: .high) {
                        await assImageRenderer?.subtitle(header: subtitleHeader)
                    }
                } else {
                    let assParse = AssParse()
                    if assParse.canParse(scanner: Scanner(string: subtitleHeader)) {
                        self.assParse = assParse
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
        var parts = text(subtitle: subtitle, start: start, end: end)
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

    func doFlushCodec() {}

    func shutdown() {
        scale.shutdown()
        avsubtitle_free(&subtitle)
        if let codecContext {
            avcodec_close(codecContext)
            avcodec_free_context(&self.codecContext)
        }
    }

    private func text(subtitle: AVSubtitle, start: TimeInterval, end: TimeInterval) -> [SubtitlePart] {
        var parts = [SubtitlePart]()
        var images = [(CGRect, CGImage)]()
        var origin: CGPoint = .zero
        var attributedString: NSMutableAttributedString?
        for i in 0 ..< Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee else {
                continue
            }
            if i == 0 {
                origin = CGPoint(x: Int(rect.x), y: Int(rect.y))
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
                        await assImageRenderer.add(subtitle: subtitle, start: Int64(start * 1000), duration: end == .infinity ? 0 : Int64((end - start) * 1000))
                    }
                } else if let assParse {
                    let scanner = Scanner(string: subtitle)
                    if let group = assParse.parsePart(scanner: scanner) {
                        group.start = start
                        group.end = end
                        parts.append(group)
                    }
                }
            } else if rect.type == SUBTITLE_BITMAP {
                // 不合并图片，有返回每个图片的rect，可以自己控制显示位置。
                // 因为字幕需要有透明度,所以不能用jpg；tif在iOS支持没有那么好，会有绿色背景； 用heic格式，展示的时候会卡主线程；所以最终用png。
                if let image = scale.transfer(format: AV_PIX_FMT_PAL8, width: rect.w, height: rect.h, data: Array(tuple: rect.data), linesize: Array(tuple: rect.linesize))?.cgImage()?.image() {
                    let imageRect = CGRect(x: Int(rect.x), y: Int(rect.y), width: Int(rect.w), height: Int(rect.h))
                    // 有些图片字幕不会带屏幕宽高，所以就取字幕自身的宽高。
                    let info = SubtitleImageInfo(rect: imageRect, image: image, displaySize: displaySize ?? CGSize(width: imageRect.maxX + imageRect.minX, height: imageRect.maxY))
                    let part = SubtitlePart(start, end, image: info)
                    parts.append(part)
                }
            }
        }
        if let attributedString {
            parts.append(SubtitlePart(start, end, attributedString: attributedString))
        }
        return parts
    }
}
