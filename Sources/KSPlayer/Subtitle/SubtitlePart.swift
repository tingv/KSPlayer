//
//  SubtitlePart.swift
//  KSPlayer
//
//  Created by kintan on 11/15/24.
//

import Foundation
import SwiftUI

extension UIImage: @unchecked Sendable {}
extension NSAttributedString: @unchecked Sendable {}
public struct SubtitleImageInfo: Sendable {
    public let rect: CGRect
    public let image: UIImage
    public let displaySize: CGSize
    public init(rect: CGRect, image: UIImage, displaySize: CGSize) {
        self.rect = rect
        self.image = image
        self.displaySize = displaySize
    }
}

public struct SubtitlePart: CustomStringConvertible, Sendable {
    public let start: TimeInterval
    public var end: TimeInterval
    public var render: Either<SubtitleImageInfo, (NSAttributedString, TextPosition?)>
    public var description: String {
        "Subtile Group start: \(start) end:\(end) text:\(String(describing: render))"
    }

    public init(_ start: TimeInterval, _ end: TimeInterval, _ string: String) {
        var text = string
        text = text.trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(of: "\r", with: "")
        self.init(start, end, attributedString: NSAttributedString(string: text))
    }

    public init(_ start: TimeInterval, _ end: TimeInterval, attributedString: NSAttributedString, textPosition: TextPosition? = nil) {
        self.start = start
        self.end = end
        render = .right((attributedString, textPosition))
    }

    public init(_ start: TimeInterval, _ end: TimeInterval, image: SubtitleImageInfo) {
        self.start = start
        self.end = end
        render = .left(image)
    }

    public init(_ start: TimeInterval, _ end: TimeInterval, render: Either<SubtitleImageInfo, (NSAttributedString, TextPosition?)>) {
        self.start = start
        self.end = end
        self.render = render
    }

    public func isEqual(time: TimeInterval) -> Bool {
        start <= time && end >= time
    }

    public var isEmpty: Bool {
        if let text, text.string.isEmpty {
            return true
        }
        return false
    }

    public var text: NSAttributedString? {
        render.right?.0
    }
}

public struct TextPosition: Equatable, Hashable, Sendable {
    public var verticalAlign: VerticalAlignment = .bottom
    public var horizontalAlign: HorizontalAlignment = .center
    public var leftMargin: CGFloat = 10
    public var rightMargin: CGFloat = 10
    #if os(tvOs)
    public var verticalMargin: CGFloat = 60
    #else
    public var verticalMargin: CGFloat = 10
    #endif
    public var edgeInsets: EdgeInsets {
        var edgeInsets = EdgeInsets()
        if verticalAlign == .bottom {
            edgeInsets.bottom = verticalMargin
        } else if verticalAlign == .top {
            edgeInsets.top = verticalMargin
        }
        if horizontalAlign == .leading {
            edgeInsets.leading = leftMargin
        } else if horizontalAlign == .trailing {
            edgeInsets.trailing = rightMargin
        }
        return edgeInsets
    }

    public var alignment: String {
        switch (verticalAlign, horizontalAlign) {
        case (.bottom, .leading):
            return "1"
        case (.bottom, .center):
            return "2"
        case (.bottom, .trailing):
            return "3"
        case (.center, .leading):
            return "4"
        case (.center, .center):
            return "5"
        case (.center, .trailing):
            return "6"
        case (.top, .leading):
            return "7"
        case (.top, .center):
            return "8"
        case (.top, .trailing):
            return "9"
        case (_, _):
            return "2"
        }
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
        left.start == right.start && left.end == right.end
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

extension [SubtitlePart] {
    func merge() -> [Either<SubtitleImageInfo, (NSAttributedString, TextPosition?)>] {
        // 对于文本字幕，如果是同一时间有多个的话，并且位置一样的话，那就进行合并换行，防止文字重叠。
        if count > 1 {
            let textPosition = self[0].render.right?.1
            var texts = compactMap { part in
                if let right = part.render.right, right.1 == textPosition {
                    return right.0
                } else {
                    return nil
                }
            }
            if texts.count == count {
                texts.reverse()
                let str = NSMutableAttributedString()
                loop(iterations: texts.count) { i in
                    if i > 0 {
                        str.append(NSAttributedString(string: "\n"))
                    }
                    str.append(texts[i])
                }
                return [Either.right((str, textPosition))]
            }
        }
        return map(\.render)
    }
}

extension CGRect: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin)
        hasher.combine(size)
    }
}

extension CGPoint: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

extension CGSize: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

extension Either<SubtitleImageInfo, (NSAttributedString, TextPosition?)>: Identifiable {
    public var id: Int {
        switch self {
        case let .left(info):
            return info.rect.hashValue
        case let .right(str, _):
            return str.hashValue
        }
    }
}
