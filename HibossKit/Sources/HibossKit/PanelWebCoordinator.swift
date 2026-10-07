// WKWebView mount handshake, message decoding and local panel resource delivery.
// Exports PanelWebCoordinator and internal panel wire/resource types.
// Dependencies: WebKit, PanelWebModel, PanelValue and PanelWebAssets.

import Foundation
import WebKit

@MainActor
public final class PanelWebCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: PanelWebModel
        var definition: [String: PanelValue]
        weak var webView: WKWebView?
        private var didLoad = false
        var mountSent = false
        #if os(iOS)
        private let generation: Int
        private var isCurrent: Bool { generation == model.reloadGeneration }
        #endif

    public init(model: PanelWebModel, definition: [String: PanelValue]) {
            self.model = model
            self.definition = definition
            #if os(iOS)
            generation = model.reloadGeneration
            #endif
        }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoad = true
            scheduleMount()
        }

        func scheduleMount() {
            guard didLoad, !mountSent else { return }
            #if os(iOS)
            Task { @MainActor [weak self] in
                let environment = ProcessInfo.processInfo.environment
                let delay = environment["HIBOSS_DEMO"] == "1"
                    ? Int(environment["HIBOSS_DEMO_WEB_DELAY_MS"] ?? "") ?? 0 : 0
                do { try await Task.sleep(for: .milliseconds(delay)) }
                catch { return }
                guard let self, !self.mountSent else { return }
                guard self.isCurrent else { return }
                self.mountSent = true
                self.model.mount(definition: self.definition)
            }
            #else
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.mountSent else { return }
                self.mountSent = true
                self.model.mount(definition: self.definition)
            }
            #endif
        }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        #if os(iOS)
        guard isCurrent else { return }
        #endif
        model.markTerminated()
    }

    public func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
            let url = navigationAction.request.url
            decisionHandler(url?.scheme == "hiboss-panel" && url?.host == "panel" ? .allow : .cancel)
        }

    public func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
            guard message.name == "hiboss", JSONSerialization.isValidJSONObject(message.body),
                  let data = try? JSONSerialization.data(withJSONObject: message.body),
                  let decoded = try? JSONDecoder().decode(PanelViewMessage.self, from: data) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                #if os(iOS)
                guard self.isCurrent else { return }
                #endif
                self.model.handle(decoded)
            }
        }

    func send(_ message: PanelHostMessage) {
            guard let webView, let data = try? JSONEncoder().encode(message),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return }
            webView.callAsyncJavaScript("window.__hibossBridge.receive(message)",
                                       arguments: ["message": object], in: nil,
                                       in: WKContentWorld.page) { _ in }
    }
}

enum PanelHostMessageKind: String, Encodable { case mount }
enum PanelViewMessageKind: String, Decodable { case contentSizeChanged, renderFailed }

struct PanelHostMessage: Encodable {
    let kind: PanelHostMessageKind
    let panelId: String
    let definition: [String: PanelValue]?
    let state: [String: PanelValue]?
    let sequence: Int
}

struct PanelViewMessage: Decodable {
    let kind: PanelViewMessageKind
    let panelId: String
    let contentHeight: Double?
    let message: String?
}

final class PanelSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "hiboss-panel",
              url.host == "panel", url.path == "/index.html" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let data = Data(PanelWebAssets.document.utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/html",
                                            expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
