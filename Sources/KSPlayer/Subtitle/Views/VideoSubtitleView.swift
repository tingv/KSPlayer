//
//  VideoSubtitleView.swift
//  KSPlayer
//
//  Created by kintan on 8/18/24.
//

import SwiftUI

public struct VideoSubtitleView: View {
    @ObservedObject
    fileprivate var model: SubtitleModel
    public init(model: SubtitleModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            ForEach(model.parts.merge()) { render in
                subtitleView(render: render)
            }
        }
        // 禁止字幕视图交互，以免抢占视图的点击事件或其它手势事件
        .allowsHitTesting(false)
        .ksIgnoresSafeArea()
    }

    @ViewBuilder
    private func subtitleView(render: Either<SubtitleImageInfo, (NSAttributedString, TextPosition?)>) -> some View {
        switch render {
        case let .left(info):
            SubtitleLeftView(info: info, isHDR: model.isHDR, screenSize: model.screenSize)
        case let .right(text, textPosition):
            SubtitleRightView(textPosition: textPosition, text: text)
                .padding([.top, .bottom], floor((model.screenSize.height - model.playSize.height) / 2))
                .frame(maxWidth: .infinity)
        }
    }
}

extension NSAttributedString {
    @MainActor
    var view: some View {
        if #available(macOS 12, iOS 15, tvOS 15, *), !KSOptions.stripSubtitleStyle {
            Text(AttributedString(self))
        } else {
            Text(string)
        }
    }
}
