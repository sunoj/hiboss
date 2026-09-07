// Display-only WKWebView leaf for chart catalog components and the seam bridge.
// Exports: PanelWebModel, PanelWebLeafSlot, and PanelWebView.
// Dependencies: WebKit, SwiftUI, PanelJSONValue, and PanelWebAssets.

import Foundation
import SwiftUI
import WebKit

private final class DisplayWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

@MainActor
final class PanelWebModel: ObservableObject {
    @Published private(set) var contentHeight: CGFloat = 48
    @Published private(set) var failureMessage: String?
    fileprivate var sendMessage: ((PanelHostMessage) -> Void)?

    func mount(definition: [String: PanelJSONValue]) {
        sendMessage?(PanelHostMessage(kind: .mount, panelId: "panels-demo", definition: definition, state: nil, sequence: 0))
    }

    fileprivate func handle(_ message: PanelViewMessage) {
        guard message.panelId == "panels-demo" else { return }
        switch message.kind {
        case .contentSizeChanged:
            guard let height = message.contentHeight, height.isFinite else { return }
            contentHeight = max(48, min(800, CGFloat(height)))
        case .renderFailed:
            failureMessage = message.message ?? "Display renderer failed"
        }
    }

    func markTerminated() { failureMessage = "Web content process terminated" }
}

struct PanelWebLeafSlot: View {
    @ObservedObject var model: PanelWebModel
    let definition: [String: PanelJSONValue]

    var body: some View {
        ZStack {
            PanelWebView(model: model, definition: definition)
            if let failure = model.failureMessage {
                Text(failure).foregroundStyle(.secondary).padding()
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, idealHeight: model.contentHeight, maxHeight: 800)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Display chart")
    }
}

struct PanelWebView: NSViewRepresentable {
    @ObservedObject var model: PanelWebModel
    let definition: [String: PanelJSONValue]

    func makeCoordinator() -> Coordinator { Coordinator(model: model, definition: definition) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(PanelSchemeHandler(), forURLScheme: "hiboss-panel")
        configuration.userContentController.add(context.coordinator, name: "hiboss")
        let webView = DisplayWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        model.sendMessage = { [weak coordinator = context.coordinator] message in coordinator?.send(message) }
        guard let url = URL(string: "hiboss-panel://panel/index.html") else { return webView }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.definition = definition
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.scheduleMount()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: PanelWebModel
        var definition: [String: PanelJSONValue]
        weak var webView: WKWebView?
        private var didLoad = false
        private var mountSent = false

        init(model: PanelWebModel, definition: [String: PanelJSONValue]) {
            self.model = model
            self.definition = definition
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoad = true
            scheduleMount()
        }

        func scheduleMount() {
            guard didLoad, !mountSent else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.mountSent else { return }
                self.mountSent = true
                self.model.mount(definition: self.definition)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { model.markTerminated() }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url?.scheme == "hiboss-panel" && url?.host == "panel" ? .allow : .cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "hiboss", JSONSerialization.isValidJSONObject(message.body), let data = try? JSONSerialization.data(withJSONObject: message.body), let decoded = try? JSONDecoder().decode(PanelViewMessage.self, from: data) else { return }
            Task { @MainActor [weak self] in self?.model.handle(decoded) }
        }

        fileprivate func send(_ message: PanelHostMessage) {
            guard let webView, let data = try? JSONEncoder().encode(message), let object = try? JSONSerialization.jsonObject(with: data) else { return }
            webView.callAsyncJavaScript("window.__hibossBridge.receive(message)", arguments: ["message": object], in: nil, in: WKContentWorld.page) { _ in }
        }
    }
}

private enum PanelHostMessageKind: String, Encodable { case mount }
private enum PanelViewMessageKind: String, Decodable { case contentSizeChanged, renderFailed }

private struct PanelHostMessage: Encodable {
    let kind: PanelHostMessageKind
    let panelId: String
    let definition: [String: PanelJSONValue]?
    let state: [String: PanelJSONValue]?
    let sequence: Int
}

private struct PanelViewMessage: Decodable {
    let kind: PanelViewMessageKind
    let panelId: String
    let contentHeight: Double?
    let message: String?
}

private final class PanelSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "hiboss-panel", url.host == "panel", url.path == "/index.html" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
        }
        let data = Data(PanelWebAssets.document.utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
