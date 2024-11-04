//
//  UIImage+Image.swift
//  KSPlayer
//
//  Created by Ian Magallan on 29.07.24.
//

import SwiftUI

extension UIImage {
    var imageView: some View {
        #if enableFeatureLiveText && canImport(VisionKit) && !targetEnvironment(simulator)
        if #available(macCatalyst 17.0, *) {
            return LiveTextImage(uiImage: self)
        } else {
            return Image(uiImage: self)
                .resizable()
        }
        #else
        return Image(uiImage: self)
            .resizable()
        #endif
    }
}
