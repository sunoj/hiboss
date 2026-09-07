// SwiftUI bridge hosting the bundled renderer in a locked-down WKWebView.
// Exports: WebPanelView and Coordinator.
// Dependencies: WebKit, SwiftUI, LocalSchemeHandler, HostModel, and BridgeTypes.

import Foundation
import SwiftUI
import WebKit

struct WebPanelView: NSViewRepresentable {
    @ObservedObject var model: HostModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "hiboss-panel")
        configuration.userContentController.add(context.coordinator, name: "hiboss")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        model.sendMessage = { [weak coordinator = context.coordinator] message in coordinator?.send(message) }
        webView.load(URLRequest(url: URL(string: "hiboss-panel://panel/index.html")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.model = model
        if context.coordinator.didLoad, context.coordinator.lastMountRevision != model.mountRevision { context.coordinator.lastMountRevision = model.mountRevision; model.mount() }
        webView.setValue(false, forKey: "drawsBackground")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var model: HostModel
        weak var webView: WKWebView?
        var didLoad = false
        var lastMountRevision = -1

        init(model: HostModel) { self.model = model }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoad = true
            lastMountRevision = model.mountRevision
            let configuredDelay = UserDefaults.standard.double(forKey: "HIBOSS_MOUNT_DELAY")
            let mountDelay = configuredDelay > 0 ? configuredDelay : 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + mountDelay) {
                self.model.mount()
                if ProcessInfo.processInfo.environment["HIBOSS_AUTO_PROBE"] == "1" || UserDefaults.standard.bool(forKey: "HIBOSS_AUTO_PROBE") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.model.runApplyProbe() } }
            }
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
