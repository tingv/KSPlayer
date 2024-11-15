//
//  SubtitleModel.swift
//  KSPlayer
//
//  Created by kintan on 11/15/24.
//

import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif
@MainActor
open class SubtitleModel: ObservableObject {
    public enum Size {
        case smaller
        case standard
        case large
        public var rawValue: CGFloat {
            switch self {
            case .smaller:
                #if os(tvOS) || os(xrOS)
                return 48
                #elseif os(macOS) || os(xrOS)
                return 20
                #else
                if UI_USER_INTERFACE_IDIOM() == .phone {
                    return 12
                } else {
                    return 20
                }
                #endif
            case .standard:
                #if os(tvOS) || os(xrOS)
                return 58
                #elseif os(macOS) || os(xrOS)
                return 26
                #else
                if UI_USER_INTERFACE_IDIOM() == .phone {
                    return 16
                } else {
                    return 26
                }
                #endif
            case .large:
                #if os(tvOS) || os(xrOS)
                return 68
                #elseif os(macOS) || os(xrOS)
                return 32
                #else
                if UI_USER_INTERFACE_IDIOM() == .phone {
                    return 20
                } else {
                    return 32
                }
                #endif
            }
        }
    }

    #if os(iOS) || os(macOS)
    @available(iOS 18.0, macOS 15.0, *)
    public var translationSession: TranslationSession? {
        get {
            _translationSession as? TranslationSession
        }
        set {
            _translationSession = newValue
        }
    }
    #endif
    public var _translationSession: Any? = nil
    private var subtitleDataSources = [SubtitleDataSource]()
    @Published
    public private(set) var subtitleInfos: [any SubtitleInfo] = KSOptions.audioRecognizes
    @Published
    public private(set) var parts = [SubtitlePart]()
    public var subtitleDelay = 0.0 // s
    public var isHDR = false
    public var screenSize = CGSize.zero
    public var url: URL {
        didSet {
            subtitleDataSources.removeAll()
            for dataSource in KSOptions.subtitleDataSources {
                addSubtitle(dataSource: dataSource)
            }
            Task { @MainActor in
                subtitleInfos.removeAll()
                subtitleInfos.append(contentsOf: KSOptions.audioRecognizes)
                parts = []
                selectedSubtitleInfo = nil
            }
        }
    }

    public var selectedSubtitleInfo: SubtitleInfo? {
        didSet {
            oldValue?.isEnabled = false
            if let selectedSubtitleInfo {
                selectedSubtitleInfo.isEnabled = true
                addSubtitle(info: selectedSubtitleInfo)
                if let info = selectedSubtitleInfo as? URLSubtitleInfo, !info.downloadURL.isFileURL, let cache = subtitleDataSources.first(where: { $0 is CacheSubtitleDataSource }) as? CacheSubtitleDataSource {
                    cache.addCache(fileURL: url, downloadURL: info.downloadURL)
                }
            }
        }
    }

    public init(url: URL) {
        self.url = url
        for dataSource in KSOptions.subtitleDataSources {
            addSubtitle(dataSource: dataSource)
        }
    }

    public func addSubtitle(info: SubtitleInfo) {
        if subtitleInfos.first(where: { $0.subtitleID == info.subtitleID }) == nil {
            subtitleInfos.append(info)
        }
    }

    public func subtitle(currentTime: TimeInterval, playSize: CGSize, screenSize: CGSize) {
        self.screenSize = screenSize
        //        KSLog("[subtitle] currentTime \(currentTime)")
        Task { @MainActor in
            var newParts = [SubtitlePart]()
            if let subtile = selectedSubtitleInfo {
                let currentTime = currentTime - subtile.delay - subtitleDelay
                newParts = await subtile.search(for: currentTime, size: playSize, isHDR: isHDR)
                if newParts.isEmpty {
                    newParts = parts.filter { part in
                        part == currentTime
                    }
                } else if newParts.allSatisfy { !$0.isEmpty } {
                    // 如果当前的字幕里面有空字幕的话，那就不要跟之前的字幕合并了。可以认为空字幕就是一个终止的信号。
                    for part in parts {
                        if part == currentTime, part.end != .infinity, newParts.allSatisfy({ $0 != part }) {
                            newParts.append(part)
                        }
                    }
                }
            }
            // swiftUI不会判断是否相等。所以需要这边判断下。
            if newParts != parts {
                #if os(iOS) || os(macOS)
                if #available(iOS 18.0, macOS 15.0, *) {
                    if let first = newParts.first, let right = first.render.right, let session = translationSession {
                        if let response = try? await session.translate(right.0.string) {
                            let str = NSMutableAttributedString(attributedString: right.0)
                            str.append(NSAttributedString(string: "\n"))
                            str.append(NSAttributedString(string: response.targetText))
                            first.render = .right((str, right.1))
                        }
                    }
                }
                #endif
                parts = newParts
            }
        }
    }

    public func searchSubtitle(query: String, languages: [String]) {
        for dataSource in subtitleDataSources {
            if let dataSource = dataSource as? SearchSubtitleDataSource {
                subtitleInfos.removeAll { info in
                    dataSource.infos.contains {
                        $0 === info
                    }
                }
                Task { @MainActor in
                    do {
                        try await subtitleInfos.append(contentsOf: dataSource.searchSubtitle(query: query, languages: languages))
                    } catch {
                        KSLog(error)
                    }
                }
            }
        }
    }

    public func addSubtitle(dataSource: SubtitleDataSource) {
        subtitleDataSources.append(dataSource)
        if let dataSource = dataSource as? URLSubtitleDataSource {
            Task { @MainActor in
                do {
                    try await subtitleInfos.append(contentsOf: dataSource.searchSubtitle(fileURL: url))
                } catch {
                    KSLog(error)
                }
            }
        } else if let dataSource = dataSource as? (any EmbedSubtitleDataSource) {
            subtitleInfos.append(contentsOf: dataSource.infos)
        }
    }
}
