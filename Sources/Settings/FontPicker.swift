import SwiftUI
import AppKit

struct FontPicker: View {
    let label: String
    @Binding var selection: String
    let monospacedOnly: Bool

    private var families: [String] {
        let all = NSFontManager.shared.availableFontFamilies
        if monospacedOnly {
            return ["(System default)"] + all.filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
            }
        }
        return ["(System default)"] + all
    }

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(families, id: \.self) { family in
                if family == "(System default)" {
                    Text(family).tag("")
                } else {
                    Text(family)
                        .font(Font.custom(family, size: 13))
                        .tag(family)
                }
            }
        }
    }
}
