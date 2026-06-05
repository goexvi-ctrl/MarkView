import Foundation

// GitHub-compatible heading-to-anchor slug algorithm.
// Rules (mirrors GitHub):
//  1. Lowercase the text.
//  2. Remove any character that is not a letter, digit, space, or hyphen.
//  3. Replace spaces with hyphens.
//  4. De-duplicate by appending -1, -2, ... on collision.
//
// The same algorithm runs in app.js on the live DOM; this Swift version
// is used for tests and for resolving incoming fragment links in Swift.
struct HeadingSlugger {

    private var counts: [String: Int] = [:]

    mutating func slug(for heading: String) -> String {
        let base = Self.baseSlug(for: heading)
        if let n = counts[base] {
            counts[base] = n + 1
            return "\(base)-\(n)"
        }
        counts[base] = 1
        return base
    }

    // Stateless single-heading slug (no de-duplication)
    static func baseSlug(for heading: String) -> String {
        heading
            .lowercased()
            .unicodeScalars
            .filter { scalar in
                let v = scalar.value
                // Keep: letters (any Unicode), digits, space, hyphen
                return CharacterSet.letters.contains(scalar)
                    || CharacterSet.decimalDigits.contains(scalar)
                    || v == 0x20  // space
                    || v == 0x2D  // hyphen
            }
            .map { String($0) }
            .joined()
            .replacingOccurrences(of: " ", with: "-")
    }
}
