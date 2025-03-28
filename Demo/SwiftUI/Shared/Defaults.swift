//
//  Defaults.swift
//  TracyPlayer
//
//  Created by kintan on 2023/7/21.
//

import Foundation
import KSPlayer
import SwiftUI

@MainActor
public class Defaults: ObservableObject {
    @AppStorage("showRecentPlayList") public var showRecentPlayList = false

    @AppStorage("hardwareDecode")
    public var hardwareDecode = KSOptions.hardwareDecode {
        didSet {
            KSOptions.hardwareDecode = hardwareDecode
        }
    }

    @AppStorage("asynchronousDecompression")
    public var asynchronousDecompression = KSOptions.asynchronousDecompression {
        didSet {
            KSOptions.asynchronousDecompression = asynchronousDecompression
        }
    }

    @AppStorage("isUseDisplayLayer")
    public var isUseDisplayLayer = MEOptions.isUseDisplayLayer {
        didSet {
            MEOptions.isUseDisplayLayer = isUseDisplayLayer
        }
    }

    @AppStorage("preferredForwardBufferDuration")
    public var preferredForwardBufferDuration = KSOptions.preferredForwardBufferDuration {
        didSet {
            KSOptions.preferredForwardBufferDuration = preferredForwardBufferDuration
        }
    }

    @AppStorage("maxBufferDuration")
    public var maxBufferDuration = KSOptions.maxBufferDuration {
        didSet {
            KSOptions.maxBufferDuration = maxBufferDuration
        }
    }

    @AppStorage("isLoopPlay")
    public var isLoopPlay = KSOptions.isLoopPlay {
        didSet {
            KSOptions.isLoopPlay = isLoopPlay
        }
    }

    @AppStorage("canBackgroundPlay")
    public var canBackgroundPlay = true {
        didSet {
            KSOptions.canBackgroundPlay = canBackgroundPlay
        }
    }

    @AppStorage("isAutoPlay")
    public var isAutoPlay = true {
        didSet {
            KSOptions.isAutoPlay = isAutoPlay
        }
    }

    @AppStorage("isSecondOpen")
    public var isSecondOpen = true {
        didSet {
            KSOptions.isSecondOpen = isSecondOpen
        }
    }

    @AppStorage("isAccurateSeek")
    public var isAccurateSeek = true {
        didSet {
            KSOptions.isAccurateSeek = isAccurateSeek
        }
    }

    @AppStorage("subtitleFontSize")
    public var subtitleFontSize = KSOptions.subtitleFontSize {
        didSet {
            KSOptions.subtitleFontSize = subtitleFontSize
        }
    }

    @AppStorage("textBold")
    public var textBold = KSOptions.textBold {
        didSet {
            KSOptions.textBold = textBold
        }
    }

    @AppStorage("textItalic")
    public var textItalic = KSOptions.textItalic {
        didSet {
            KSOptions.textItalic = textItalic
        }
    }

    @AppStorage("textColor")
    public var textColor = KSOptions.textColor {
        didSet {
            KSOptions.textColor = textColor
        }
    }

    @AppStorage("textBackgroundColor")
    public var textBackgroundColor = KSOptions.textBackgroundColor {
        didSet {
            KSOptions.textBackgroundColor = textBackgroundColor
        }
    }

    @AppStorage("horizontalAlign")
    public var horizontalAlign = KSOptions.textPosition.horizontalAlign {
        didSet {
            KSOptions.textPosition.horizontalAlign = horizontalAlign
        }
    }

    @AppStorage("verticalAlign")
    public var verticalAlign = KSOptions.textPosition.verticalAlign {
        didSet {
            KSOptions.textPosition.verticalAlign = verticalAlign
        }
    }

    @AppStorage("leftMargin")
    public var leftMargin = KSOptions.textPosition.leftMargin {
        didSet {
            KSOptions.textPosition.leftMargin = leftMargin
        }
    }

    @AppStorage("rightMargin")
    public var rightMargin = KSOptions.textPosition.rightMargin {
        didSet {
            KSOptions.textPosition.rightMargin = rightMargin
        }
    }

    @AppStorage("verticalMargin")
    public var verticalMargin = KSOptions.textPosition.verticalMargin {
        didSet {
            KSOptions.textPosition.verticalMargin = verticalMargin
        }
    }

    @AppStorage("yadifMode")
    public var yadifMode = MEOptions.yadifMode {
        didSet {
            MEOptions.yadifMode = yadifMode
        }
    }

    @AppStorage("audioPlayerType")
    public var audioPlayerType = NSStringFromClass(KSOptions.audioPlayerType) {
        didSet {
            KSOptions.audioPlayerType = NSClassFromString(audioPlayerType) as! any AudioOutput.Type
        }
    }

    public static let shared = Defaults()
    @MainActor
    private init() {
        KSOptions.hardwareDecode = hardwareDecode
        MEOptions.isUseDisplayLayer = isUseDisplayLayer
        KSOptions.subtitleFontSize = subtitleFontSize
        KSOptions.textBold = textBold
        KSOptions.textItalic = textItalic
        KSOptions.textColor = textColor
        KSOptions.textBackgroundColor = textBackgroundColor
        KSOptions.textPosition.horizontalAlign = horizontalAlign
        KSOptions.textPosition.verticalAlign = verticalAlign
        KSOptions.textPosition.leftMargin = leftMargin
        KSOptions.textPosition.rightMargin = rightMargin
        KSOptions.textPosition.verticalMargin = verticalMargin
        KSOptions.preferredForwardBufferDuration = preferredForwardBufferDuration
        KSOptions.maxBufferDuration = maxBufferDuration
        KSOptions.isLoopPlay = isLoopPlay
        KSOptions.canBackgroundPlay = canBackgroundPlay
        KSOptions.isAutoPlay = isAutoPlay
        KSOptions.isSecondOpen = isSecondOpen
        KSOptions.isAccurateSeek = isAccurateSeek
        MEOptions.yadifMode = yadifMode
        KSOptions.audioPlayerType = NSClassFromString(audioPlayerType) as! any AudioOutput.Type
    }
}

@propertyWrapper
public struct Default<T>: DynamicProperty {
    @ObservedObject private var defaults: Defaults
    private let keyPath: ReferenceWritableKeyPath<Defaults, T>
    public init(_ keyPath: ReferenceWritableKeyPath<Defaults, T>, defaults: Defaults = .shared) {
        self.keyPath = keyPath
        self.defaults = defaults
    }

    public var wrappedValue: T {
        get { defaults[keyPath: keyPath] }
        nonmutating set { defaults[keyPath: keyPath] = newValue }
    }

    public var projectedValue: Binding<T> {
        Binding(
            get: { defaults[keyPath: keyPath] },
            set: { value in
                defaults[keyPath: keyPath] = value
            }
        )
    }
}
