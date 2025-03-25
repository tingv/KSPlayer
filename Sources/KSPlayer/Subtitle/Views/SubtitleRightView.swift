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
    let screenWidth: Double
    var body: some View {
        let textPosition = textPosition ?? KSOptions.textPosition
        let alignment = Alignment(horizontal: textPosition.horizontalAlign, vertical: textPosition.verticalAlign)
        return ZStack(alignment: alignment) {
            Color.clear
            text.view
                .font(Font(KSOptions.textFont(width: screenWidth)))
                .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                .foregroundColor(KSOptions.textColor)
                .background(KSOptions.textBackgroundColor)
            #if !os(tvOS)
                .textSelection()
            #endif
                .padding(textPosition.edgeInsets)
                .if(textPosition.horizontalAlign == .center) {
                    $0.multilineTextAlignment(.center)
                }
        }
        .if(textPosition != KSOptions.textPosition && KSOptions.stripSubtitleStyle) {
            $0.padding(KSOptions.textPosition.edgeInsets)
        }
    }
}

#if DEBUG
struct SubtitleRightView_Previews: PreviewProvider {
    static var previews: some View {
        SubtitleRightView(text: NSAttributedString(string: "SubtitleRightView_Previews"), textPosition: nil, screenWidth: 384)
    }
}
#endif
