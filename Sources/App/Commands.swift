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

// Visual (magnifying glass) zoom - separate from font size / reflow zoom.
// This drives WKWebView.magnification for pure visual scale without layout reflow.
private let visualZoomMin: CGFloat = 0.25
private let visualZoomMax: CGFloat = 5.0
private let visualZoomStep: CGFloat = 0.10

private func clampedVisualZoom(_ v: CGFloat) -> CGFloat {
    min(max(v, visualZoomMin), visualZoomMax)
}

@MainActor
func visualZoomIn() {
    guard let ctrl = DocumentWindowRegistry.shared.focusedController() else { return }
    let current = ctrl.visualZoomFactor
    ctrl.setVisualZoom(clampedVisualZoom(current * (1 + visualZoomStep)))
}

@MainActor
func visualZoomOut() {
    guard let ctrl = DocumentWindowRegistry.shared.focusedController() else { return }
    let current = ctrl.visualZoomFactor
    ctrl.setVisualZoom(clampedVisualZoom(current / (1 + visualZoomStep)))
}

@MainActor
func visualZoomReset() {
    guard let ctrl = DocumentWindowRegistry.shared.focusedController() else { return }
    ctrl.setVisualZoom(1.0)
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

    @IBAction func performVisualZoomIn(_ sender: Any?) {
        MarkView.visualZoomIn()
    }

    @IBAction func performVisualZoomOut(_ sender: Any?) {
        MarkView.visualZoomOut()
    }

    @IBAction func performVisualZoomReset(_ sender: Any?) {
        MarkView.visualZoomReset()
    }
}
