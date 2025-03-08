//
//  KSSubtitle.swift
//  Pods
//
//  Created by kintan on 2017/4/2.
//
//

import Foundation
#if canImport(Translation)
import Translation
#endif

public protocol KSSubtitleProtocol {
    func search(for time: TimeInterval, size: CGSize, isHDR: Bool) async -> [SubtitlePart]
}

public extension URL {
    func parseSubtitle(userAgent: String? = nil, encoding: String.Encoding? = nil) async throws -> KSSubtitleProtocol {
        let string = try await string(userAgent: userAgent, encoding: encoding)
        guard let subtitle = string else {
            throw NSError(errorCode: .subtitleUnEncoding)
        }
        let scanner = Scanner(string: subtitle)
        _ = scanner.scanCharacters(from: .controlCharacters)
        let parse = KSOptions.subtitleParses.first { $0.canParse(scanner: scanner) }
        if let parse {
            return parse.parse(scanner: scanner)
        } else {
            throw NSError(errorCode: .subtitleFormatUnSupport)
        }
    }

    //    public static func == (lhs: KSURLSubtitle, rhs: KSURLSubtitle) -> Bool {
    //        lhs.url == rhs.url
    //    }
}

public protocol SubtitleInfo: KSSubtitleProtocol, AnyObject {
    var subtitleID: String { get }
    var name: String { get }
    var delay: TimeInterval { get }
    //    var userInfo: NSMutableDictionary? { get set }
    //    var subtitleDataSouce: SubtitleDataSouce? { get set }
//    var comment: String? { get }
    var isEnabled: Bool { get set }
    var isSrt: Bool { get }
}

public extension SubtitleInfo {
    var id: String { subtitleID }
    var isSrt: Bool { true }
    func hash(into hasher: inout Hasher) {
        hasher.combine(subtitleID)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.subtitleID == rhs.subtitleID
    }
}

public protocol NumericComparable {
    associatedtype Compare
    static func < (lhs: Self, rhs: Compare) -> Bool
    static func == (lhs: Self, rhs: Compare) -> Bool
}

extension Collection where Element: NumericComparable {
    func binarySearch(key: Element.Compare) -> Self.Index? {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let midIndex = index(lowerBound, offsetBy: distance(from: lowerBound, to: upperBound) / 2)
            if self[midIndex] == key {
                return midIndex
            } else if self[midIndex] < key {
                lowerBound = index(lowerBound, offsetBy: 1)
            } else {
                upperBound = midIndex
            }
        }
        return nil
    }
}

public protocol AudioRecognize: SubtitleInfo {
    #if (os(iOS) || os(macOS)) && !targetEnvironment(macCatalyst)
    @available(iOS 18.0, macOS 15.0, *)
    var translationSessionConf: TranslationSession.Configuration? { get }
    #endif
    func append(frame: AudioFrame)
}

public final class EmptySubtitleInfo: SubtitleInfo {
    public var isEnabled: Bool = true
    public let subtitleID: String = ""
    public var delay: TimeInterval = 0
    public let name = "no show subtitle".localized
    public func search(for _: TimeInterval, size _: CGSize, isHDR _: Bool) -> [SubtitlePart] {
        []
    }
}

public final class URLSubtitleInfo: SubtitleInfo, @unchecked Sendable {
    private var searchProtocol: KSSubtitleProtocol?
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled, searchProtocol == nil {
                Task { [weak self] in
                    guard let self else { return }
                    searchProtocol = try? await downloadURL.parseSubtitle(userAgent: userAgent)
                }
            }
        }
    }

    public private(set) var downloadURL: URL
    public var delay: TimeInterval = 0
    public private(set) var name: String
    public let subtitleID: String
    public var comment: String?
    public var userInfo: NSMutableDictionary?
    private let userAgent: String?
    public convenience init(url: URL) {
        self.init(subtitleID: url.absoluteString, name: url.lastPathComponent, url: url)
    }

    public init(subtitleID: String, name: String, url: URL, userAgent: String? = nil) {
        self.subtitleID = subtitleID
        self.name = name
        self.userAgent = userAgent
        downloadURL = url
        if !url.isFileURL, name.isEmpty {
            url.download(userAgent: userAgent) { [weak self] filename, tmpUrl in
                guard let self else {
                    return
                }
                self.name = filename
                downloadURL = tmpUrl
                var fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                fileURL.appendPathComponent(filename)
                try? FileManager.default.moveItem(at: tmpUrl, to: fileURL)
                downloadURL = fileURL
            }
        }
    }

    public var isSrt: Bool {
        name.hasSuffix("srt") || downloadURL.pathExtension == "srt"
    }

    public func search(for time: TimeInterval, size: CGSize, isHDR: Bool) async -> [SubtitlePart] {
        await searchProtocol?.search(for: time, size: size, isHDR: isHDR) ?? []
    }
}
