import SwiftUI

// iPad viewer app: a single window holding all open documents as tabs
// (DocumentTabsView). Documents arrive via the in-app file picker, the
// Files app / other apps' share sheets (declared document types, opened
// in place), and the markview:// URL scheme - all delivered through
// onOpenURL and funneled into the tabs model.
@main
struct MarkViewPadApp: App {

    var body: some Scene {
        WindowGroup {
            DocumentTabsView()
        }
    }
}
