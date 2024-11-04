//
//  SubtitleRightView.swift
//  KSPlayer
//
//  Created by Ian Magallan on 29.07.24.
//

import SwiftUI

struct SubtitleRightView: View {
    let textPosition: TextPosition?
    let text: NSAttributedString

    var body: some View {
        VStack {
            let textPosition = textPosition ?? KSOptions.textPosition
            if textPosition.verticalAlign == .bottom || textPosition.verticalAlign == .center {
                Spacer()
            }
            text.view
                .italic(value: KSOptions.textItalic)
                .font(Font(KSOptions.textFont))
                .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                .foregroundColor(KSOptions.textColor)
                .background(KSOptions.textBackgroundColor)
                .multilineTextAlignment(.center)
                .alignmentGuide(textPosition.horizontalAlign) {
                    $0[.leading]
                }
                .padding(textPosition.edgeInsets)
            #if !os(tvOS)
                .textSelection()
            #endif
            if textPosition.verticalAlign == .top || textPosition.verticalAlign == .center {
                Spacer()
            }
        }
    }
}
