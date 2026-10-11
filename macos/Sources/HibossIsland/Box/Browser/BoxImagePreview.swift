// In-app Box image preview using the authenticated original file rather than its thumbnail.
// Exports: BoxImagePreview with fit, zoom, retry, original-file and Escape/Close actions.
// Dependencies: SwiftUI, AppKit, ImageIO and BoxBrowserMedia's authenticated download cache.

import AppKit
import HibossKit
import ImageIO
import SwiftUI

struct BoxImagePreview: View {
    let item: BoxItem
    @ObservedObject var media: BoxBrowserMedia
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var file: URL?
    @State private var error: String?
    @State private var zoom: CGFloat?
    @State private var fittedScale: CGFloat = 1
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding()
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, idealWidth: 900, maxWidth: 1200,
               minHeight: 360, idealHeight: 650, maxHeight: 900)
        .background(TodayStyle.surface)
        .task(id: attempt) { await load() }
        .accessibilityIdentifier("box.image.preview")
    }

    private var toolbar: some View {
        HStack {
            Text(verbatim: item.text ?? L("Image")).font(.headline).lineLimit(1)
            Spacer()
            Button(L("Fit")) { zoom = nil }.disabled(image == nil)
            Button { zoom = max(0.1, (zoom ?? fittedScale) / 1.5) } label: {
                Image(systemName: "minus.magnifyingglass")
            }.disabled(image == nil).accessibilityLabel(L("Zoom out"))
            Button { zoom = min(4, (zoom ?? fittedScale) * 1.5) } label: {
                Image(systemName: "plus.magnifyingglass")
            }.disabled(image == nil).accessibilityLabel(L("Zoom in"))
            if let file { Link(L("Open original"), destination: file) }
            Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("box.preview.close")
        }
    }

    @ViewBuilder private var content: some View {
        if let image {
            GeometryReader { geometry in
                let fit = min(1, geometry.size.width / image.size.width,
                              geometry.size.height / image.size.height)
                let scale = zoom ?? fit
                ScrollView([.horizontal, .vertical]) {
                    BoxPreviewImage(image: image)
                        .frame(width: image.size.width * scale, height: image.size.height * scale)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .onAppear { fittedScale = fit }
                .onChange(of: geometry.size) { fittedScale = fit }
            }
        } else if let error {
            VStack(spacing: 12) {
                Label(L("Image unavailable"), systemImage: "photo")
                Text(verbatim: error).foregroundStyle(.secondary)
                Button(L("Retry image")) { attempt += 1 }
            }.padding()
        } else { ProgressView(L("Loading image…")) }
    }

    private func load() async {
        error = nil
        guard let url = await media.load(item) else {
            if !Task.isCancelled { error = media.errors[item.id] ?? L("Couldn't open this item.") }
            return
        }
        let decoded = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
        guard !Task.isCancelled else { return }
        guard let decoded else {
            error = L("Image unavailable")
            return
        }
        image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        file = url
    }
}

private struct BoxPreviewImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.identifier = NSUserInterfaceItemIdentifier("box.preview.image")
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) { view.image = image }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
