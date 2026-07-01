import Testing
import Foundation
@testable import OpenAppLock

struct CopyCatalogTests {
    // Every key must resolve to a real catalog value, not fall back to its raw key.
    @Test func everyKeyResolvesToACatalogValue() {
        for key in CopyKey.allCases {
            let resolved = key.string
            #expect(resolved != key.rawValue, "Missing catalog entry for key '\(key.rawValue)'")
            #expect(!resolved.isEmpty, "Empty catalog value for key '\(key.rawValue)'")
        }
    }

    // No resolved copy may contain dumb typography.
    @Test func everyValueUsesSmartTypography() {
        for key in CopyKey.allCases {
            let v = key.string
            #expect(!v.contains("'"), "Straight apostrophe in '\(key.rawValue)': \(v)")
            #expect(!v.contains("\""), "Straight double quote in '\(key.rawValue)': \(v)")
            #expect(!v.contains("..."), "Literal three-dot ellipsis in '\(key.rawValue)': \(v)")
        }
    }
}
