//
//  KSSubtitle.swift
//  Pods
//
//  Created by kintan on 2017/4/2.
//
//

import CoreFoundation
import CoreGraphics
import Foundation
import SwiftUI

public struct SubtitleImageInfo {
    public let rect: CGRect
    public let image: UIImage
    public let displaySize: CGSize
    public init(rect: CGRect, image: UIImage, displaySize: CGSize) {
        self.rect = rect
        self.image = image
        self.displaySize = displaySize
    }
}

public class SubtitlePart: CustomStringConvertible, Identifiable, SubtitlePartProtocol {
    public var start: TimeInterval
    public var end: TimeInterval
    public var textPosition: TextPosition?
    public var render: Either<SubtitleImageInfo, NSAttributedString>
    public var description: String {
        "Subtile Group ==========\nstart: \(start)\nend:\(end)\ntext:\(String(describing: render))"
    }

    public convenience init(_ start: TimeInterval, _ end: TimeInterval, _ string: String) {
        var text = string
        text = text.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: "\r", with: "")
        self.init(start, end, attributedString: NSAttributedString(string: text))
    }

    public init(_ start: TimeInterval, _ end: TimeInterval, attributedString: NSAttributedString) {
        self.start = start
        self.end = end
        render = .right(attributedString)
    }

    public init(_ start: TimeInterval, _ end: TimeInterval, image: SubtitleImageInfo) {
        self.start = start
        self.end = end
        render = .left(image)
    }

    public init(_ start: TimeInterval, _ end: TimeInterval, render: Either<SubtitleImageInfo, NSAttributedString>) {
        self.start = start
        self.end = end
        self.render = render
    }

    public func render(size _: CGSize) -> SubtitlePart {
        self
    }

    public func isEqual(time: TimeInterval) -> Bool {
        start <= time && end >= time
    }
}

public protocol SubtitlePartProtocol: Equatable {
    func render(size: CGSize) -> SubtitlePart
    func isEqual(time: TimeInterval) -> Bool
}

public struct TextPosition {
    public var verticalAlign: VerticalAlignment = .bottom
    public var horizontalAlign: HorizontalAlignment = .center
    public var leftMargin: CGFloat = 0
    public var rightMargin: CGFloat = 0
    public var verticalMargin: CGFloat = 10
    public var edgeInsets: EdgeInsets {
        var edgeInsets = EdgeInsets()
        if verticalAlign == .bottom {
            edgeInsets.bottom = verticalMargin
        } else if verticalAlign == .top {
            edgeInsets.top = verticalMargin
        }
        if horizontalAlign == .leading {
            edgeInsets.leading = leftMargin
        }
        if horizontalAlign == .trailing {
            edgeInsets.trailing = rightMargin
        }
        return edgeInsets
    }

    public mutating func ass(alignment: String?) {
        switch alignment {
        case "1":
            verticalAlign = .bottom
            horizontalAlign = .leading
        case "2":
            verticalAlign = .bottom
            horizontalAlign = .center
        case "3":
            verticalAlign = .bottom
            horizontalAlign = .trailing
        case "4":
            verticalAlign = .center
            horizontalAlign = .leading
        case "5":
            verticalAlign = .center
            horizontalAlign = .center
        case "6":
            verticalAlign = .center
            horizontalAlign = .trailing
        case "7":
            verticalAlign = .top
            horizontalAlign = .leading
        case "8":
            verticalAlign = .top
            horizontalAlign = .center
        case "9":
            verticalAlign = .top
            horizontalAlign = .trailing
        default:
            break
        }
    }
}

extension SubtitlePart: Comparable {
    public static func == (left: SubtitlePart, right: SubtitlePart) -> Bool {
        left.start == right.start && left.end == right.end && left.render.right == right.render.right
    }

    public static func < (left: SubtitlePart, right: SubtitlePart) -> Bool {
        if left.start < right.start {
            return true
        } else {
            return false
        }
    }
}

extension SubtitlePart: NumericComparable {
    public typealias Compare = TimeInterval
    public static func == (left: SubtitlePart, right: TimeInterval) -> Bool {
        left.start <= right && left.end >= right
    }

    public static func < (left: SubtitlePart, right: TimeInterval) -> Bool {
        left.end < right
    }
}

public protocol KSSubtitleProtocol {
    func search(for time: TimeInterval, size: CGSize) async -> [SubtitlePart]
}

public protocol SubtitleInfo: KSSubtitleProtocol, AnyObject, Hashable, Identifiable {
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
    public func search(for time: TimeInterval, size: CGSize) async -> [SubtitlePart] {
        await searchProtocol?.search(for: time, size: size) ?? []
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

    private var subtitleDataSouces = [SubtitleDataSouce]()
    @Published
    public private(set) var subtitleInfos = [any SubtitleInfo]()
    @Published
    public private(set) var parts = [SubtitlePart]()
    public var subtitleDelay = 0.0 // s
    public var isHDR = false
    public var url: URL {
        didSet {
            subtitleDataSouces.removeAll()
            for datasouce in KSOptions.subtitleDataSouces {
                addSubtitle(dataSouce: datasouce)
            }
            Task { @MainActor in
                subtitleInfos.removeAll()
                subtitleInfos.append(contentsOf: KSOptions.audioRecognizes)
                parts = []
                selectedSubtitleInfo = nil
            }
        }
    }

    @Published
    public var selectedSubtitleInfo: (any SubtitleInfo)? {
        didSet {
            oldValue?.isEnabled = false
            if let selectedSubtitleInfo {
                selectedSubtitleInfo.isEnabled = true
                addSubtitle(info: selectedSubtitleInfo)
                if let info = selectedSubtitleInfo as? URLSubtitleInfo, !info.downloadURL.isFileURL, let cache = subtitleDataSouces.first(where: { $0 is CacheSubtitleDataSouce }) as? CacheSubtitleDataSouce {
                    cache.addCache(fileURL: url, downloadURL: info.downloadURL)
                }
            }
        }
    }

    public init(url: URL) {
        self.url = url
        for datasouce in KSOptions.subtitleDataSouces {
            addSubtitle(dataSouce: datasouce)
        }
    }

    public func addSubtitle(info: any SubtitleInfo) {
        if subtitleInfos.first(where: { $0.subtitleID == info.subtitleID }) == nil {
            subtitleInfos.append(info)
        }
    }

    public func subtitle(currentTime: TimeInterval, size: CGSize) {
        Task { @MainActor in
            var newParts = [SubtitlePart]()
            if let subtile = selectedSubtitleInfo {
                let currentTime = currentTime - subtile.delay - subtitleDelay
                newParts = await subtile.search(for: currentTime, size: size)
                if newParts.isEmpty {
                    newParts = parts.filter { part in
                        part == currentTime
                    }
                }
            }
            // swiftUI不会判断是否相等。所以需要这边判断下。
            if newParts != parts {
                parts = newParts
            }
        }
    }

    public func searchSubtitle(query: String, languages: [String]) {
        for dataSouce in subtitleDataSouces {
            if let dataSouce = dataSouce as? SearchSubtitleDataSouce {
                subtitleInfos.removeAll { info in
                    dataSouce.infos.contains {
                        $0 === info
                    }
                }
                Task { @MainActor in
                    do {
                        try await subtitleInfos.append(contentsOf: dataSouce.searchSubtitle(query: query, languages: languages))
                    } catch {
                        KSLog(error)
                    }
                }
            }
        }
    }

    public func addSubtitle(dataSouce: SubtitleDataSouce) {
        subtitleDataSouces.append(dataSouce)
        if let dataSouce = dataSouce as? URLSubtitleDataSouce {
            Task { @MainActor in
                do {
                    try await subtitleInfos.append(contentsOf: dataSouce.searchSubtitle(fileURL: url))
                } catch {
                    KSLog(error)
                }
            }
        } else if let dataSouce = dataSouce as? (any EmbedSubtitleDataSouce) {
            subtitleInfos.append(contentsOf: dataSouce.infos)
        }
    }
}
