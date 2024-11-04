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
}
