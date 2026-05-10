import CoreGraphics
import Foundation

// Private CoreGraphics symbols for querying Mission-Control Spaces.
// Linked via @_silgen_name; they live inside the CoreGraphics framework.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: UInt32) -> Unmanaged<CFArray>

/// Read-only snapshot of the current Mission-Control Space layout.
enum SpaceQuery {

    /// (count, currentIndex) for the *first* managed display, where the count
    /// includes both regular Spaces and full-screen-app Spaces, in left-to-right
    /// order. Returns nil if private API output cannot be parsed.
    static func mainDisplayLayout() -> (count: Int, currentIndex: Int)? {
        let cid = CGSMainConnectionID()
        let raw = CGSCopyManagedDisplaySpaces(cid).takeRetainedValue()
        guard let displays = raw as? [[String: Any]],
              let first = displays.first,
              let spaces = first["Spaces"] as? [[String: Any]]
        else { return nil }

        let ids: [Int] = spaces.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.intValue }
        guard !ids.isEmpty else { return nil }

        var currentIndex = 0
        if let cur = first["Current Space"] as? [String: Any],
           let curId = (cur["ManagedSpaceID"] as? NSNumber)?.intValue,
           let idx = ids.firstIndex(of: curId) {
            currentIndex = idx
        }
        return (ids.count, currentIndex)
    }
}
