//
//  EmbedDataSouce.swift
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
}

extension FFmpegAssetTrack: KSSubtitleProtocol {
    public func search(for time: TimeInterval, size: CGSize) async -> [SubtitlePart] {
        if let sutitleRender {
            return await sutitleRender.search(for: time, size: size)
        }
        return subtitle?.outputRenderQueue.search { item -> Bool in
            item.part.isEqual(time: time)
        }.map(\.part) ?? []
    }
}

extension KSMEPlayer: EmbedSubtitleDataSouce {
    public var infos: [FFmpegAssetTrack] {
        tracks(mediaType: .subtitle).compactMap { $0 as? FFmpegAssetTrack }
    }
}
