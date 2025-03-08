//
//  String+Localized.swift
//
//
//  Created by Ian Magallan on 23.07.24.
//

import Foundation

extension String {
    var localized: String {
        NSLocalizedString(self, tableName: nil, bundle: .module, comment: "")
    }
//    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
//    var localized: LocalizedStringResource {
//        LocalizedStringResource(String.LocalizationValue(self), bundle: .module)
//    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension LocalizedStringResource.BundleDescription {
    /// 方便计算 _这个_ Swift 包的 `BundleDescription` 的属性
    static let module: LocalizedStringResource.BundleDescription = .atURL(Bundle.module.bundleURL)
}
