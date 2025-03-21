//
//  AssParse.swift
//  KSPlayer
//
//  Created by kintan on 9/14/24.
//

import Foundation
import SwiftUI

public class AssParse: KSParseProtocol {
    private var styleMap = [String: ASSStyle]()
    private var eventKeys = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]
    private var playResX = Float(0.0)
    private var playResY = Float(0.0)
    public func canParse(scanner: Scanner) -> Bool {
        // 兼容不规范的ass字幕
        guard let info = scanner.scanUpToCharacters(from: .newlines), info.contains("[Script Info]") else {
            return false
        }
        while scanner.scanString("Format:") == nil {
            if scanner.scanString("PlayResX:") != nil {
                playResX = scanner.scanFloat() ?? 0
            } else if scanner.scanString("PlayResY:") != nil {
                playResY = scanner.scanFloat() ?? 0
            } else {
                _ = scanner.scanUpToCharacters(from: .newlines)
            }
        }
        guard var keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
            return false
        }
        keys = keys.map { $0.trimmingCharacters(in: .whitespaces) }
        while scanner.scanString("Style:") != nil {
            _ = scanner.scanString("Format: ")
            guard let values = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
                continue
            }
            var dic = [String: String]()
            for i in 1 ..< keys.count {
                dic[keys[i]] = values[i]
            }
            styleMap[values[0]] = dic.parseASSStyle()
        }
        _ = scanner.scanString("[Events]")
        if scanner.scanString("Format: ") != nil {
            guard let keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
                return false
            }
            eventKeys = keys.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return true
    }

    // Dialogue: 0,0:12:37.73,0:12:38.83,Aki Default,,0,0,0,,{\be8}原来如此
    // ffmpeg 软解的字幕
    // 875,,Default,NTP,0000,0000,0000,!Effect,- 你们两个别冲这么快\\N- 我会取消所有行程尽快赶过去
    public func parsePart(scanner: Scanner) -> SubtitlePart? {
        let isDialogue = scanner.scanString("Dialogue") != nil
        var dic = [String: String]()
        for i in 0 ..< eventKeys.count {
            if !isDialogue, i == 1 {
                continue
            }
            if i == eventKeys.count - 1 {
                dic[eventKeys[i]] = scanner.scanUpToCharacters(from: .newlines)
            } else {
                dic[eventKeys[i]] = scanner.scanUpToString(",")
                _ = scanner.scanString(",")
            }
        }
        let start: TimeInterval
        let end: TimeInterval
        if let startString = dic["Start"], let endString = dic["End"] {
            start = startString.parseDuration()
            end = endString.parseDuration()
        } else {
            if isDialogue {
                return nil
            } else {
                start = 0
                end = 0
            }
        }
        var attributes: [NSAttributedString.Key: Any]?
        var textPosition: TextPosition
        if let style = dic["Style"], let assStyle = styleMap.match(key: style) {
            attributes = assStyle.attrs
            textPosition = assStyle.textPosition
            if let marginL = dic["MarginL"].flatMap(Double.init), marginL != 0 {
                textPosition.leftMargin = CGFloat(marginL)
            }
            if let marginR = dic["MarginR"].flatMap(Double.init), marginR != 0 {
                textPosition.rightMargin = CGFloat(marginR)
            }
            if let marginV = dic["MarginV"].flatMap(Double.init), marginV != 0 {
                textPosition.verticalMargin = CGFloat(marginV)
            }
        } else {
            textPosition = TextPosition()
        }
        guard var text = dic["Text"] else {
            return nil
        }
        text = text.replacingOccurrences(of: "\\N", with: "\n")
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        text = text.replacingOccurrences(of: "\\h", with: " ")
        let part = SubtitlePart(start, end, attributedString: text.build(textPosition: &textPosition, attributed: attributes), textPosition: textPosition)
        return part
    }
}

public extension Dictionary where Key == String {
    func match(key: String) -> Value? {
        if key.hasPrefix("*") {
            let newKey = String(key.suffix(from: key.index(key.startIndex, offsetBy: 1)))
            return first { element in
                element.key.hasSuffix(newKey)
            }?.1
        } else if key.hasSuffix("*") {
            let newKey = String(key.prefix(upTo: key.index(key.endIndex, offsetBy: -1)))
            return first { element in
                element.key.hasPrefix(newKey)
            }?.1
        } else {
            return self[key]
        }
    }
}

public struct ASSStyle {
    let attrs: [NSAttributedString.Key: Any]
    let textPosition: TextPosition
}

// swiftlint:disable cyclomatic_complexity
extension String {
    func build(textPosition: inout TextPosition, attributed: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {
        let lineCodes = splitStyle()
        let attributedStr = NSMutableAttributedString()
        var attributed = attributed ?? [:]
        for lineCode in lineCodes {
            attributedStr.append(lineCode.0.parseStyle(attributes: &attributed, style: lineCode.1, textPosition: &textPosition))
        }
        return attributedStr
    }

    func splitStyle() -> [(String, String?)] {
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = nil
        var result = [(String, String?)]()
        var sytle: String?
        while !scanner.isAtEnd {
            if scanner.scanString("{") != nil {
                sytle = scanner.scanUpToString("}")
                _ = scanner.scanString("}")
            } else if let text = scanner.scanUpToString("{") {
                result.append((text, sytle))
            } else if let text = scanner.scanUpToCharacters(from: .newlines) {
                result.append((text, sytle))
            }
        }
        return result
    }

    func parseStyle(attributes: inout [NSAttributedString.Key: Any], style: String?, textPosition: inout TextPosition) -> NSAttributedString {
        guard let style else {
            let attributedStr = NSMutableAttributedString()
            let scanner = Scanner(string: self)
            while !scanner.isAtEnd {
                if let text = scanner.scanUpToString("<") {
                    attributedStr.append(NSAttributedString(string: text, attributes: attributes))
                }
                if scanner.scanString("<font") != nil {
                    if let attrString = scanner.parseFontStyle(attributes: attributes) {
                        attributedStr.append(attrString)
                    }
                }
                if let text = scanner.scanUpToCharacters(from: .newlines) {
                    attributedStr.append(NSAttributedString(string: text, attributes: attributes))
                }
            }
            return attributedStr
        }
        var fontName: String?
        var fontSize: Float?
        let subStyleArr = style.components(separatedBy: "\\")
        var shadow = attributes[.shadow] as? NSShadow
        for item in subStyleArr {
            let itemStr = item.replacingOccurrences(of: " ", with: "")
            let scanner = Scanner(string: itemStr)
            let char = scanner.scanCharacter()
            switch char {
            case "a":
                let char = scanner.scanCharacter()
                if char == "n" {
                    textPosition.ass(alignment: scanner.scanUpToCharacters(from: .newlines))
                }
            case "b":
                attributes[.expansion] = scanner.scanFloat()
            case "c":
                attributes[.foregroundColor] = scanner.scanUpToCharacters(from: .newlines).flatMap(UIColor.init(assColor:))
            case "f":
                let char = scanner.scanCharacter()
                if char == "n" {
                    fontName = scanner.scanUpToCharacters(from: .newlines)
                } else if char == "s" {
                    fontSize = scanner.scanFloat()
                }
            case "i":
                attributes[.obliqueness] = scanner.scanFloat()
            case "s":
                if scanner.scanString("had") != nil {
                    if let size = scanner.scanFloat() {
                        shadow = shadow ?? NSShadow()
                        shadow?.shadowOffset = CGSize(width: CGFloat(size), height: CGFloat(size))
                        shadow?.shadowBlurRadius = CGFloat(size)
                    }
                    attributes[.shadow] = shadow
                } else {
                    attributes[.strikethroughStyle] = scanner.scanInt()
                }
            case "u":
                attributes[.underlineStyle] = scanner.scanInt()
            case "1", "2", "3", "4":
                let twoChar = scanner.scanCharacter()
                if twoChar == "c" {
                    let color = scanner.scanUpToCharacters(from: .newlines).flatMap(UIColor.init(assColor:))
                    if char == "1" {
                        attributes[.foregroundColor] = color
                    } else if char == "2" {
                        // 还不知道这个要设置到什么颜色上
                        //                        attributes[.backgroundColor] = color
                    } else if char == "3" {
                        attributes[.strokeColor] = color
                    } else if char == "4" {
                        shadow = shadow ?? NSShadow()
                        shadow?.shadowColor = color
                        attributes[.shadow] = shadow
                    }
                }
            default:
                break
            }
        }
        // Apply font attributes if available
        if let fontName, let fontSize {
            let font = UIFont(name: fontName, size: CGFloat(fontSize)) ?? UIFont.systemFont(ofSize: CGFloat(fontSize))
            attributes[.font] = font
        }
        return NSAttributedString(string: self, attributes: attributes)
    }
}

extension Scanner {
    func parseFontStyle(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString? {
        var attributes = attributes
        var fontName: String?
        if scanString("face=\"") != nil, let name = scanUpToString("\""), scanString("\"") != nil {
            fontName = name
        }
        var font: UIFont?
        if scanString("size=\"") != nil, let fontSize = scanFloat(), scanString("\"") != nil {
            if let fontName {
                font = UIFont(name: fontName, size: CGFloat(fontSize))
            }
            font = font ?? UIFont.systemFont(ofSize: CGFloat(fontSize))
        }
        if scanString("color=\"#") != nil, let hex = scanInt(representation: .hexadecimal), scanString("\"") != nil {
            attributes[.foregroundColor] = UIColor(rgb: hex)
        }
        if scanString(">") != nil, var text = scanUpToString("</font>") {
            scanString("</font>")
            if text.hasPrefix("<i>"), text.hasSuffix("</i>") {
                text.removeFirst(3)
                text.removeLast(4)
                font = font?.union(symbolicTrait: .traitItalic)
            }
            attributes[.font] = font
            return NSAttributedString(string: text, attributes: attributes)
        }
        return nil
    }
}

public extension [String: String] {
    func parseASSStyle() -> ASSStyle {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let fontName = self["Fontname"], let fontSize = self["Fontsize"].flatMap(Double.init) {
            let fontDescriptor: UIFontDescriptor
            if let degrees = self["Angle"].flatMap(Double.init), degrees != 0 {
                let radians = CGFloat(degrees * .pi / 180.0)
                #if !canImport(UIKit)
                let matrix = AffineTransform(rotationByRadians: radians)
                #else
                let matrix = CGAffineTransform(rotationAngle: radians)
                #endif
                fontDescriptor = UIFontDescriptor(name: fontName, matrix: matrix)
            } else {
                fontDescriptor = UIFontDescriptor(name: fontName, size: fontSize)
            }
            let bold = self["Bold"] == "1"
            let italic = self["Italic"] == "1"
            var symbolicTraits = fontDescriptor.symbolicTraits
            if bold {
                symbolicTraits = symbolicTraits.union(.traitBold)
            }
            if italic {
                symbolicTraits = symbolicTraits.union(.traitItalic)
            }
            let descriptor = fontDescriptor.withSymbolicTraits(symbolicTraits) ?? fontDescriptor
            let font = UIFont(descriptor: descriptor, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
            attributes[.font] = font
        }
        // 创建字体样式
        if let assColor = self["PrimaryColour"] {
            attributes[.foregroundColor] = UIColor(assColor: assColor)
        }
        // 还不知道这个要设置到什么颜色上
        if let assColor = self["SecondaryColour"] {
            //            attributes[.backgroundColor] = UIColor(assColor: assColor)
        }
        if self["Underline"] == "1" {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if self["StrikeOut"] == "1" {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        //        if let scaleX = self["ScaleX"].flatMap(Double.init), scaleX != 100 {
        //            attributes[.expansion] = scaleX / 100.0
        //        }
        //        if let scaleY = self["ScaleY"].flatMap(Double.init), scaleY != 100 {
        //            attributes[.baselineOffset] = scaleY - 100.0
        //        }

        //        if let spacing = self["Spacing"].flatMap(Double.init) {
        //            attributes[.kern] = CGFloat(spacing)
        //        }

        if self["BorderStyle"] == "1" {
            if let strokeWidth = self["Outline"].flatMap(Double.init), strokeWidth > 0 {
                attributes[.strokeWidth] = -strokeWidth
                if let assColor = self["OutlineColour"] {
                    attributes[.strokeColor] = UIColor(assColor: assColor)
                }
                if let assColor = self["BackColour"] {
                    let shadow = NSShadow()
                    if let shadowOffset = self["Shadow"].flatMap(Double.init) {
                        shadow.shadowOffset = CGSize(width: CGFloat(shadowOffset), height: CGFloat(shadowOffset))
                    }
                    shadow.shadowBlurRadius = strokeWidth
                    shadow.shadowColor = UIColor(assColor: assColor)
                    attributes[.shadow] = shadow
                }
            }
        }
        var textPosition = TextPosition()
        textPosition.ass(alignment: self["Alignment"])
        if let marginL = self["MarginL"].flatMap(Double.init) {
            textPosition.leftMargin = CGFloat(marginL)
        }
        if let marginR = self["MarginR"].flatMap(Double.init) {
            textPosition.rightMargin = CGFloat(marginR)
        }
        if let marginV = self["MarginV"].flatMap(Double.init) {
            textPosition.verticalMargin = CGFloat(marginV)
        }
        return ASSStyle(attrs: attributes, textPosition: textPosition)
    }
    // swiftlint:enable cyclomatic_complexity
}

extension UIFont {
    convenience init?(name: String, size: Double, bold: Bool, italic: Bool) {
        let fontDescriptor = UIFontDescriptor(name: name, size: size)
        var symbolicTraits = fontDescriptor.symbolicTraits
        if bold {
            symbolicTraits = symbolicTraits.union(.traitBold)
        }
        if italic {
            symbolicTraits = symbolicTraits.union(.traitItalic)
        }
        let descriptor = fontDescriptor.withSymbolicTraits(symbolicTraits) ?? fontDescriptor
        self.init(descriptor: descriptor, size: size)
    }

    func union(symbolicTrait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var fontDescriptor = fontDescriptor
        var symbolicTraits = fontDescriptor.symbolicTraits
        symbolicTraits = symbolicTraits.union(symbolicTrait)
        let descriptor = fontDescriptor.withSymbolicTraits(symbolicTraits) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
