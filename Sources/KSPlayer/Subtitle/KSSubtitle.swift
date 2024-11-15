//
//  KSSubtitle.swift
//  Pods
//
//  Created by kintan on 2017/4/2.
//
//

import Foundation

public protocol SubtitlePartProtocol: Equatable {
    func render(size: CGSize) -> SubtitlePart
    func isEqual(time: TimeInterval) -> Bool
}

public protocol KSSubtitleProtocol {
    func search(for time: TimeInterval, size: CGSize, isHDR: Bool) async -> [SubtitlePart]
}

public protocol SubtitleInfo: KSSubtitleProtocol, AnyObject {
    var subtitleID: String { get }
    var name: String { get }
    var delay: TimeInterval { get set }
    //    var userInfo: NSMutableDictionary? { get set }
    //    var subtitleDataSouce: SubtitleDataSouce? { get set }
//    var comment: String? { get }
    var isEnabled: Bool { get set }
}

public extension SubtitleInfo {
    var id: String { subtitleID }
    func hash(into hasher: inout Hasher) {
        hasher.combine(subtitleID)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.subtitleID == rhs.subtitleID
    }
}

public class KSSubtitle {
    public var searchProtocol: KSSubtitleProtocol?
    public init() {}
}

extension KSSubtitle: KSSubtitleProtocol {
    /// Search for target group for time
    public func search(for time: TimeInterval, size: CGSize, isHDR: Bool) async -> [SubtitlePart] {
        await searchProtocol?.search(for: time, size: size, isHDR: isHDR) ?? []
    }
}

public extension KSSubtitle {
    func parse(url: URL, userAgent: String? = nil, encoding: String.Encoding? = nil) async throws {
        let string = try await url.string(userAgent: userAgent, encoding: encoding)
        guard let subtitle = string else {
            throw NSError(errorCode: .subtitleUnEncoding)
        }
        let scanner = Scanner(string: subtitle)
        _ = scanner.scanCharacters(from: .controlCharacters)
        let parse = KSOptions.subtitleParses.first { $0.canParse(scanner: scanner) }
        if let parse {
            searchProtocol = parse.parse(scanner: scanner)
        } else {
            throw NSError(errorCode: .subtitleFormatUnSupport)
        }
    }

//    public static func == (lhs: KSURLSubtitle, rhs: KSURLSubtitle) -> Bool {
//        lhs.url == rhs.url
//    }
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
    func append(frame: AudioFrame)
}

public class EmptySubtitleInfo: SubtitleInfo {
    public var isEnabled: Bool = true
    public let subtitleID: String = ""
    public var delay: TimeInterval = 0
    public let name = NSLocalizedString("no show subtitle", comment: "")
    public func search(for _: TimeInterval, size _: CGSize, isHDR _: Bool) -> [SubtitlePart] {
        []
    }
}

public class URLSubtitleInfo: KSSubtitle, SubtitleInfo {
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled, searchProtocol == nil {
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.parse(url: self.downloadURL, userAgent: self.userAgent)
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
        super.init()
        if !url.isFileURL, name.isEmpty {
            url.download(userAgent: userAgent) { [weak self] filename, tmpUrl in
                guard let self else {
                    return
                }
                self.name = filename
                self.downloadURL = tmpUrl
                var fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                fileURL.appendPathComponent(filename)
                try? FileManager.default.moveItem(at: tmpUrl, to: fileURL)
                self.downloadURL = fileURL
            }
        }
    }
}
