//
//  Extensions.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//


import Foundation
import UIKit
import SwiftData
import ObjectiveC

// MARK: - Model Context Extension Only

extension UIViewController {
    private static var modelContextKey: UInt8 = 0
    
    var modelContext: ModelContext? {
        get {
            return objc_getAssociatedObject(self, &Self.modelContextKey) as? ModelContext
        }
        set {
            objc_setAssociatedObject(self, &Self.modelContextKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

// MARK: - Date Formatting Extensions

extension Date {
    func formatted(date dateStyle: DateFormatter.Style, time timeStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: self)
    }
}
