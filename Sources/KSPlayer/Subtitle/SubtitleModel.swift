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
                if UIDevice.current.userInterfaceIdiom == .phone {
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
                if UIDevice.current.userInterfaceIdiom == .phone {
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
                if UIDevice.current.userInterfaceIdiom == .phone {
                    return 20
                } else {
                    return 32
                }
                #endif
            }
        }
    }

    #if (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
    private var _translationSessionConf: Any?
    @available(iOS 18.0, macOS 15.0, *)
    public var translationSessionConf: TranslationSession.Configuration? {
        get {
            _translationSessionConf as? TranslationSession.Configuration
        }
        set {
            _translationSessionConf = newValue
            if newValue == nil {
                translationSession = nil
            }
        }
    }

    private var _translationSession: Any?
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
    private var subtitleDataSources = [SubtitleDataSource]()
    @Published
    public private(set) var subtitleInfos = [any SubtitleInfo]()
    @Published
    public private(set) var parts = [SubtitlePart]()
    public var subtitleDelay = 0.0 // s
    public var isHDR = false
    public var playRatio = Double(1)
    @Published
    public var screenSize = CGSize.zero
    public var url: URL {
        didSet {
            subtitleDataSources.removeAll()
            for dataSource in KSOptions.subtitleDataSources {
                addSubtitle(dataSource: dataSource)
            }
            Task { @MainActor in
                subtitleInfos.removeAll()
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
                #if (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
                if #available(iOS 18.0, macOS 15.0, *) {
                    translationSessionConf = (selectedSubtitleInfo as? AudioRecognize)?.translationSessionConf
                }
                #endif
                addSubtitle(info: selectedSubtitleInfo)
                if let info = selectedSubtitleInfo as? URLSubtitleInfo, !info.downloadURL.isFileURL, let cache = subtitleDataSources.first(where: { $0 is CacheSubtitleDataSource }) as? CacheSubtitleDataSource {
                    cache.addCache(fileURL: url, downloadURL: info.downloadURL)
                }
            }
        }
    }

    public var textVerticalPadding: Double {
        // 如何屏幕上下有黑边的话。那就让文字字幕出现在上下黑边里面
        if playRatio.isHorizonal != screenSize.isHorizonal || playRatio < screenSize.ratio {
            let playSize = screenSize.within(ratio: playRatio)
            return floor((screenSize.height - playSize.height) / 2)
        } else {
            return 0
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

    public func subtitle(currentTime: TimeInterval, playRatio: Double, screenSize: CGSize) {
        self.playRatio = playRatio
        if self.screenSize != screenSize {
            self.screenSize = screenSize
        }
        //        KSLog("[subtitle] currentTime \(currentTime)")
        Task { @MainActor in
            var newParts = [SubtitlePart]()
            if let subtile = selectedSubtitleInfo {
                var playSize = screenSize
                // 如何屏幕上下有黑边的话。那就让srt字幕出现在上下黑边里面。ass是有绝对位置的，所以一定要按照视频的比率来计算
                if !subtile.isSrt || playRatio.isHorizonal != screenSize.isHorizonal || playRatio < screenSize.ratio {
                    playSize = screenSize.within(ratio: playRatio)
                }
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
                #if (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
                if #available(iOS 18.0, macOS 15.0, *) {
                    if let first = newParts.first, let right = first.render.right {
                        if let response = try? await translationSession?.translate(right.0.string) {
                            let str = NSMutableAttributedString()
                            if KSOptions.showTranslateSourceText {
                                str.append(right.0)
                                str.append(NSAttributedString(string: "\n"))
                            }
                            str.append(NSAttributedString(string: response.targetText))
                            newParts = [SubtitlePart(first.start, first.end, render: .right((str, right.1)))]
                        }
                    }
                }
                #endif
                parts = newParts
            }
        }
    }

    public func cleanParts() {
        parts = []
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
        } else if let dataSource = dataSource as? (any ConstantSubtitleDataSource) {
            for info in dataSource.infos {
                addSubtitle(info: info)
            }
        }
    }
}
