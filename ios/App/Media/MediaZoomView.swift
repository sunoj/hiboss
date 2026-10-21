// Pinch and double-tap zoom wrapper used by the shared media viewer.
// Exports: MediaZoomView.
// Dependencies: AVKit, SwiftUI, UIKit, MediaSwipeDismiss.

import AVKit
import SwiftUI
import UIKit

struct MediaZoomView<Content: View>: UIViewRepresentable {
    let pageID: String
    var allowsZoom = true
    var onZoomed: (Bool) -> Void
    var onDismissDrag: (CGFloat) -> Void
    var onDismiss: () -> Void
    var onSingleTap: () -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onZoomed: onZoomed,
            onDismissDrag: onDismissDrag,
            onDismiss: onDismiss,
            onSingleTap: onSingleTap,
            content: content()
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = context.coordinator.makeScrollView()
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleTapped(_:))
        )
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.singleTapped)
        )
        singleTap.cancelsTouchesInView = false
        singleTap.delegate = scroll as? ZoomScrollView
        singleTap.require(toFail: tap)
        scroll.addGestureRecognizer(singleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onZoomed = onZoomed
        context.coordinator.onDismissDrag = onDismissDrag
        context.coordinator.onDismiss = onDismiss
        context.coordinator.onSingleTap = onSingleTap
        scroll.maximumZoomScale = allowsZoom ? 4 : 1
        context.coordinator.host.rootView = content()
        context.coordinator.syncFrame(scroll)
        if context.coordinator.pageID != pageID {
            context.coordinator.pageID = pageID
            scroll.setZoomScale(1, animated: false)
            DispatchQueue.main.async { onZoomed(false) }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onZoomed: (Bool) -> Void
        var onDismissDrag: (CGFloat) -> Void
        var onDismiss: () -> Void
        var onSingleTap: () -> Void
        var pageID = ""
        let host: UIHostingController<Content>
        weak var scroll: UIScrollView?

        init(
            onZoomed: @escaping (Bool) -> Void,
            onDismissDrag: @escaping (CGFloat) -> Void,
            onDismiss: @escaping () -> Void,
            onSingleTap: @escaping () -> Void,
            content: Content
        ) {
            self.onZoomed = onZoomed
            self.onDismissDrag = onDismissDrag
            self.onDismiss = onDismiss
            self.onSingleTap = onSingleTap
            host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            // Not attached as a child VC: UIViewRepresentable has no parent to addChild.
            // Safe here — we size the hosted view explicitly in syncFrame; lifecycle /
            // safe-area forwarding is unused. Switching to UIViewControllerRepresentable
            // would parent it but would not fix the zero-bounds layout bug on its own.
        }

        func makeScrollView() -> UIScrollView {
            let scroll = ZoomScrollView()
            scroll.delegate = self
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = 4
            scroll.bouncesZoom = true
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.backgroundColor = .systemBackground
            scroll.accessibilityIdentifier = "media-zoom-scroll host:0x0@0,0"
            scroll.accessibilityValue = String(localized: "Fitted")
            scroll.addSubview(host.view)
            scroll.onBoundsChange = { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                self.syncFrame(scroll)
            }
            scroll.onDismissDrag = { [weak self] in self?.onDismissDrag($0) }
            scroll.onDismiss = { [weak self] in self?.onDismiss() }
            self.scroll = scroll
            return scroll
        }

        func syncFrame(_ scroll: UIScrollView) {
            let size = scroll.bounds.size
            guard size.width > 0, size.height > 0, scroll.zoomScale == 1 else {
                publishHostSize(scroll)
                return
            }
            let frame = CGRect(origin: .zero, size: size)
            if host.view.frame != frame {
                host.view.frame = frame
            }
            if scroll.contentSize != size {
                scroll.contentSize = size
            }
            publishHostSize(scroll)
        }

        /// Exposes the UIKit host frame to UI tests via accessibilityIdentifier.
        /// (SwiftUI AX frames can look correct while the hosting UIView is still 0x0.)
        private func publishHostSize(_ scroll: UIScrollView) {
            let f = host.view.frame
            scroll.accessibilityIdentifier = String(
                format: "media-zoom-scroll host:%.0fx%.0f@%.0f,%.0f",
                f.width, f.height, f.origin.x, f.origin.y
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > MediaSwipeDismiss.zoomedScale
            scrollView.accessibilityValue = zoomed
                ? String(localized: "Zoomed") : String(localized: "Fitted")
            DispatchQueue.main.async { [onZoomed] in onZoomed(zoomed) }
        }

        @objc func singleTapped() { onSingleTap() }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll, scroll.maximumZoomScale > 1 else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
                return
            }
            let point = gesture.location(in: host.view)
            let size = scroll.bounds.size
            let rect = CGRect(
                x: point.x - size.width / 4,
                y: point.y - size.height / 4,
                width: size.width / 2,
                height: size.height / 2
            )
            scroll.zoom(to: rect, animated: true)
        }
    }
}

/// Relays bounds changes so the hosted SwiftUI view can track the scroll view after layout.
/// `updateUIView` alone is too early — bounds are still zero before the first layout pass.
private final class ZoomScrollView: UIScrollView, UIGestureRecognizerDelegate {
    var onBoundsChange: (() -> Void)?
    var onDismissDrag: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?
    private var lastBoundsSize: CGSize = .zero
    private let dismissPan = UIPanGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        dismissPan.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        dismissPan.cancelsTouchesInView = false
        dismissPan.maximumNumberOfTouches = 1
        addGestureRecognizer(dismissPan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size != lastBoundsSize else { return }
        lastBoundsSize = size
        onBoundsChange?()
    }

    @objc func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let y = MediaSwipeDismiss.dragOffset(
            translation: gesture.translation(in: self),
            zoomScale: zoomScale
        )
        switch gesture.state {
        case .changed:
            onDismissDrag?(y)
        case .ended, .cancelled, .failed:
            if MediaSwipeDismiss.shouldDismiss(offset: y, zoomScale: zoomScale) {
                onDismiss?()
            } else {
                onDismissDrag?(0)
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGestureRecognizer {
            return zoomScale > MediaSwipeDismiss.zoomedScale
        }
        guard gestureRecognizer == dismissPan else { return true }
        return MediaSwipeDismiss.shouldBegin(
            zoomScale: zoomScale,
            velocity: dismissPan.velocity(in: self)
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        if let tap = gestureRecognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired == 1,
           other is UITapGestureRecognizer {
            var responder: UIResponder? = other.view
            while let current = responder {
                if current is AVPlayerViewController { return true }
                responder = current.next
            }
        }
        return gestureRecognizer == dismissPan && other == panGestureRecognizer
    }
}
