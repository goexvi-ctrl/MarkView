import AppKit
import SwiftUI

// Non-modal banner shown at the bottom of the document view.
// Transient banners auto-dismiss after ~4 s; persistent ones stay until
// explicitly dismissed or until the document is reloaded.

enum BannerStyle { case info, warning, error }

// MARK: - SwiftUI body

private struct BannerBody: View {
    let message: String
    let style: BannerStyle
    let onDismiss: () -> Void

    private var bg: Color {
        switch style {
        case .info:    return Color(NSColor.systemBlue)
        case .warning: return Color(NSColor.systemOrange)
        case .error:   return Color(NSColor.systemRed)
        }
    }
    private var icon: String {
        switch style {
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .font(.system(size: 13))
            Text(message)
                .foregroundStyle(.white)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bg.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
    }
}

// MARK: - NSView wrapper

final class InfoBannerView: NSView {
    private let hosting: NSHostingView<BannerBody>
    private var dismissTask: DispatchWorkItem?

    init(message: String, style: BannerStyle, onDismiss: @escaping () -> Void) {
        hosting = NSHostingView(
            rootView: BannerBody(message: message, style: style, onDismiss: onDismiss)
        )
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// MARK: - MarkdownWebViewController extension

extension MarkdownWebViewController {

    private static var bannerKey = "infoBanner"
    private static var bannerTaskKey = "infoBannerTask"

    private var currentBanner: InfoBannerView? {
        get { objc_getAssociatedObject(self, &Self.bannerKey) as? InfoBannerView }
        set { objc_setAssociatedObject(self, &Self.bannerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private var bannerDismissTask: DispatchWorkItem? {
        get { objc_getAssociatedObject(self, &Self.bannerTaskKey) as? DispatchWorkItem }
        set { objc_setAssociatedObject(self, &Self.bannerTaskKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func showBanner(_ message: String,
                    style: BannerStyle = .warning,
                    autoDismiss: Bool = true) {
        dismissBanner()

        let banner = InfoBannerView(message: message, style: style) { [weak self] in
            self?.dismissBanner()
        }
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            banner.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
        currentBanner = banner

        if autoDismiss {
            let work = DispatchWorkItem { [weak self] in self?.dismissBanner() }
            bannerDismissTask = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
        }
    }

    func dismissBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        currentBanner?.removeFromSuperview()
        currentBanner = nil
    }
}
