//
//  SubtitleRightView.swift
//  KSPlayer
//
//  Created by Ian Magallan on 29.07.24.
//

import SwiftUI

struct SubtitleRightView: View {
    let text: NSAttributedString
    let textPosition: TextPosition?
    var body: some View {
        VStack {
            let textPosition = textPosition ?? KSOptions.textPosition
            if textPosition.verticalAlign == .bottom || textPosition.verticalAlign == .center {
                Spacer()
            }
            text.view
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

#if DEBUG
struct SubtitleRightView_Previews: PreviewProvider {
    static var previews: some View {
        SubtitleRightView(text: NSAttributedString(string: "SubtitleRightView_Previews"), textPosition: nil)
    }
}
#endif
