import SwiftUI
import AppKit

// Zoom: 10 % multiplicative steps, clamped to [0.5, 3.0], rounded to 2 dp.
private let zoomMin: Double = 0.5
private let zoomMax: Double = 3.0
private let zoomStep: Double = 0.10  // relative step

private func clampedZoom(_ v: Double) -> Double {
    (min(max(v, zoomMin), zoomMax) * 100).rounded() / 100
}

@MainActor
func zoomIn() {
    guard let ctrl = DocumentWindowRegistry.shared.focusedController() else { return }
    ctrl.setZoom(clampedZoom(ctrl.zoomFactor * (1 + zoomStep)))
}

@MainActor
func zoomOut() {
    guard let ctrl = DocumentWindowRegistry.shared.focusedController() else { return }
    ctrl.setZoom(clampedZoom(ctrl.zoomFactor / (1 + zoomStep)))
}

@MainActor
func zoomReset() {
    guard let ctrl = DocumentWindowRegistry.shared.focusedController() else { return }
    ctrl.setZoom(1.0)
}

// MARK: - Target-action handlers on AppDelegate (first responder chain)

extension AppDelegate {
    @IBAction func openDocument(_ sender: Any?) {
        showOpenPanel()
    }

    @IBAction func performZoomIn(_ sender: Any?) {
        MarkView.zoomIn()
    }

    @IBAction func performZoomOut(_ sender: Any?) {
        MarkView.zoomOut()
    }

    @IBAction func performZoomReset(_ sender: Any?) {
        MarkView.zoomReset()
    }
}
