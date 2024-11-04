//
//  SubtitleLeftView.swift
//  KSPlayer
//
//  Created by Ian Magallan on 29.07.24.
//

import SwiftUI

struct SubtitleLeftView: View {
    let info: SubtitleImageInfo
    let isHDR: Bool
    let screenSize: CGSize
    var body: some View {
        let rect = info.displaySize.convert(rect: info.rect, toSize: screenSize)
        // 不能加scaledToFit。不然的话图片的缩放比率会有问题。
        info.image.imageView
            .if(isHDR) {
                $0.allowedDynamicRange()
            }
            .frame(width: rect.width, height: rect.height)
            .position(CGPoint(x: rect.midX, y: rect.midY))
    }
}
