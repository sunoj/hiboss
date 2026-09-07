// Display-only WKWebView leaf and its native host-side seam state.
// Exports: WebLeafModel, WebLeafSlot, and WebLeafView.
// Dependencies: WebKit, SwiftUI, BridgeTypes, and the bundled web resource.

import Foundation
import SwiftUI
import WebKit

private final class DisplayWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

@MainActor
final class WebLeafModel: ObservableObject {
    @Published private(set) var contentHeight: CGFloat = 240
    @Published private(set) var failureMessage: String?
    private(set) var heightHistory: [CGFloat] = []
    private(set) var messageCount = 0
    var sendMessage: ((HostMessage) -> Void)?
    var onFailure: ((String) -> Void)?

    func mount(definition: [String: JSONValue]) {
        sendMessage?(HostMessage(kind: .mount, panelId: "seam-panel", definition: definition, state: ["chartHeight": .number(240)], sequence: 0))
    }

    func applyChartHeight(_ height: CGFloat, sequence: Int) {
        sendMessage?(HostMessage(kind: .applyTaskState, panelId: "seam-panel", definition: nil, state: ["chartHeight": .number(Double(height))], sequence: sequence))
    }

    func handle(_ message: ViewMessage) {
        guard message.panelId == "seam-panel" else { return }
        messageCount += 1
        switch message.kind {
        case .contentSizeChanged:
            guard let height = message.contentHeight, height.isFinite else { return }
            contentHeight = max(48, min(800, CGFloat(height)))
            heightHistory.append(contentHeight)
        case .renderFailed:
            let text = message.message ?? "Display renderer failed"
            failureMessage = text
            onFailure?(text)
        }
    }

    func markTerminated() {
        let text = "Web content process terminated"
        failureMessage = text
        onFailure?(text)
    }

    func clearFailure() { failureMessage = nil }
}

struct WebLeafSlot: View {
    @ObservedObject var model: WebLeafModel
    let definition: [String: JSONValue]

    var body: some View {
        ZStack {
            WebLeafView(model: model, definition: definition)
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

struct WebLeafView: NSViewRepresentable {
    @ObservedObject var model: WebLeafModel
    let definition: [String: JSONValue]

    func makeCoordinator() -> Coordinator { Coordinator(model: model, definition: definition) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "hiboss-panel")
        configuration.userContentController.add(context.coordinator, name: "hiboss")
        let webView = DisplayWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        model.sendMessage = { [weak coordinator = context.coordinator] message in coordinator?.send(message) }
        webView.load(URLRequest(url: URL(string: "hiboss-panel://panel/index.html")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.definition = definition
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.scheduleMount()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: WebLeafModel
        var definition: [String: JSONValue]
        weak var webView: WKWebView?
        var didLoad = false
        var mountSent = false
        var mountScheduled = false

        init(model: WebLeafModel, definition: [String: JSONValue]) {
            self.model = model
            self.definition = definition
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoad = true
            scheduleMount()
        }

        func scheduleMount() {
            guard didLoad, !mountSent, !mountScheduled else { return }
            mountScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, !self.mountSent else { return }
                self.mountSent = true
                self.model.mount(definition: self.definition)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            model.markTerminated()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            decisionHandler(url?.scheme == "hiboss-panel" && url?.host == "panel" ? .allow : .cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "hiboss", JSONSerialization.isValidJSONObject(message.body), let data = try? JSONSerialization.data(withJSONObject: message.body), let decoded = try? JSONDecoder().decode(ViewMessage.self, from: data) else { return }
            Task { @MainActor [weak self] in self?.model.handle(decoded) }
        }

        func send(_ message: HostMessage) {
            guard let webView, let data = try? JSONEncoder().encode(message), let object = try? JSONSerialization.jsonObject(with: data) else { return }
            webView.callAsyncJavaScript("window.__hibossBridge.receive(message)", arguments: ["message": object], in: nil, in: WKContentWorld.page) { _ in }
        }
    }
}
