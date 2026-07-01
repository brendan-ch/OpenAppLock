import SwiftUI

extension Text {
    /// `Text(.onboardingRequesting)` — compile-checked copy at SwiftUI call sites.
    init(_ key: CopyKey) { self.init(key.resource) }
}
