//
//  EmbedDataSource.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import Foundation
import Libavcodec
import Libavutil

extension FFmpegAssetTrack: SubtitleInfo {
    public var subtitleID: String {
        String(trackID)
    }

    public var isSrt: Bool {
        [AV_CODEC_ID_SRT, AV_CODEC_ID_WEBVTT, AV_CODEC_ID_TEXT, AV_CODEC_ID_SUBRIP, AV_CODEC_ID_MOV_TEXT].contains(codecpar.codec_id)
    }
}

extension FFmpegAssetTrack: KSSubtitleProtocol {
    public func search(for time: TimeInterval, size: CGSize, isHDR: Bool) async -> [SubtitlePart] {
        if let subtitleRender {
            return await subtitleRender.search(for: time, size: size, isHDR: isHDR)
        }
        let parts = subtitle?.outputRenderQueue.search { item -> Bool in
            item.part.isEqual(time: time)
        }.map(\.part)
        guard var parts, !parts.isEmpty else {
            return []
        }
        var prePart: SubtitlePart?
        loop(iterations: parts.count) { i in
            /// pgssub字幕会没有结束时间，所以会插入空的字幕，但是空的字幕有可能跟非空的字幕在同一个数组里面
            /// 这样非空字幕就无法清除了。所以这边需要更新下字幕的结束时间。（字幕有进行了排序了）
            // 需要判断下字幕的开始时间是否一样
            if i > 0, parts[i - 1].end == .infinity, parts[i].isEmpty || parts[i].start > parts[i - 1].start {
                parts[i - 1].end = parts[i].start
            }
            if KSOptions.isResizeImageSubtitle, let left = parts[i].render.left {
                // 图片字幕的比例可能跟视频的比例不一致，所以需要对图片的大小进行伸缩下
                var hZoom = size.width / left.displaySize.width
                var vZoom = size.height / left.displaySize.height
                var newRect = left.rect * (hZoom, vZoom)
                parts[i].render = .left(SubtitleImageInfo(rect: newRect.integral, image: left.image, displaySize: size))
            }
        }
        return parts
    }
}

extension KSMEPlayer: ConstantSubtitleDataSource {
    @MainActor
    public var infos: [FFmpegAssetTrack] {
        tracks(mediaType: .subtitle).compactMap { $0 as? FFmpegAssetTrack }
    }
}
