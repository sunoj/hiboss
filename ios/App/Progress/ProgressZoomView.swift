// Pinch and double-tap zoom wrapper used by the progress media viewer.
// Exports: ProgressZoomView.
// Dependencies: SwiftUI, UIKit.

import SwiftUI
import UIKit

struct ProgressZoomView<Content: View>: UIViewRepresentable {
    let pageID: String
    var onZoomed: (Bool) -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomed: onZoomed, content: content())
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = context.coordinator.makeScrollView()
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleTapped(_:))
        )
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onZoomed = onZoomed
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
        var pageID = ""
        let host: UIHostingController<Content>
        weak var scroll: UIScrollView?

        init(onZoomed: @escaping (Bool) -> Void, content: Content) {
            self.onZoomed = onZoomed
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
            scroll.backgroundColor = .black
            scroll.accessibilityIdentifier = "progress-zoom-scroll host:0x0@0,0"
            scroll.addSubview(host.view)
            scroll.onBoundsChange = { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                self.syncFrame(scroll)
            }
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
                format: "progress-zoom-scroll host:%.0fx%.0f@%.0f,%.0f",
                f.width, f.height, f.origin.x, f.origin.y
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.01
            DispatchQueue.main.async { [onZoomed] in onZoomed(zoomed) }
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll else { return }
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
private final class ZoomScrollView: UIScrollView {
    var onBoundsChange: (() -> Void)?
    private var lastBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size != lastBoundsSize else { return }
        lastBoundsSize = size
        onBoundsChange?()
    }
}
