// Display-only WKWebView leaf shared by the macOS and iOS panel renderers.
// Exports: PanelWebModel, PanelWebLeafSlot, and PanelWebView.
// Dependencies: WebKit, SwiftUI, PanelValue, and the package web resource.

import Foundation
import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#endif

private final class DisplayWebView: WKWebView {
#if os(macOS)
    override var acceptsFirstResponder: Bool { false }
#endif
}

@MainActor
public final class PanelWebModel: ObservableObject {
    @Published private(set) var contentHeight: CGFloat = 48
    @Published private(set) var failureMessage: String?
    #if os(iOS)
    @Published private(set) var isReady = false
    @Published private(set) var reloadGeneration = 0

    public func retryDisplay() {
        isReady = false
        failureMessage = nil
        reloadGeneration += 1
    }
    #endif
    var sendMessage: ((PanelHostMessage) -> Void)?

    public func mount(definition: [String: PanelValue]) {
        sendMessage?(
            PanelHostMessage(
                kind: .mount, panelId: "panels-demo", definition: definition, state: nil, sequence: 0))
    }

    func handle(_ message: PanelViewMessage) {
        guard message.panelId == "panels-demo" else { return }
        switch message.kind {
        case .contentSizeChanged:
            guard let height = message.contentHeight, height.isFinite else { return }
            contentHeight = max(48, min(800, CGFloat(height)))
            #if os(iOS)
            isReady = true
            #endif
        case .renderFailed:
            failureMessage = message.message ?? kitL("Display renderer failed")
        }
    }

    public func markTerminated() { failureMessage = kitL("Web content process terminated") }
}

public struct PanelWebLeafSlot: View {
    public let definition: [String: PanelValue]
    @ObservedObject private var store: PanelStore
    @StateObject private var model = PanelWebModel()
    #if os(iOS)
    @ScaledMetric(relativeTo: .callout) private var pendingHeight: CGFloat = 180
    #endif

    public init(definition: [String: PanelValue], store: PanelStore) {
        self.definition = definition
        _store = ObservedObject(wrappedValue: store)
    }

    public var body: some View {
        let resolvedDefinition = resolvedWebLeafDefinition(definition, state: store.state)
        ZStack {
            PanelWebView(model: model, definition: resolvedDefinition)
                #if os(iOS)
                .id(model.reloadGeneration)
                #endif
            if let failure = model.failureMessage {
                #if os(iOS)
                VStack {
                    Text(verbatim: failure).foregroundStyle(NativePendingTheme.secondary)
                    Button(kitL("Retry display")) { model.retryDisplay() }.frame(minHeight: 44)
                }.padding().background(.regularMaterial)
                #else
                Text(verbatim: failure).foregroundStyle(.secondary).padding()
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(.regularMaterial)
                #endif
            }
            #if os(iOS)
            if model.failureMessage == nil && !model.isReady {
                NativePendingNotice(title: kitL("Loading display…"), retry: { model.retryDisplay() })
                    .id(model.reloadGeneration)
                    .padding().background(.regularMaterial)
            }
            #endif
        }
        #if os(iOS)
        .frame(maxWidth: .infinity)
        .frame(height: model.isReady ? model.contentHeight : max(model.contentHeight, pendingHeight))
        .accessibilityElement(children: .contain)
        #else
        .frame(maxWidth: .infinity, minHeight: 48, idealHeight: model.contentHeight, maxHeight: 800)
        .accessibilityElement(children: .ignore)
        #endif
        .accessibilityLabel(
            resolvedDefinition["type"]?.string == "Table" ? kitL("Display table") : kitL("Display chart"))
    }
}

func resolvedWebLeafDefinition(_ definition: [String: PanelValue], state: PanelValue) -> [String: PanelValue]
{
    var resolved = definition.mapValues { resolveWebLeafValue($0, state: state) }
    // A Table binds its live rows through `rowsBinding`; the renderers read `rows`, so a bound
    // array becomes the rows once resolved and literal rows keep precedence.
    if resolved["rows"]?.array == nil, let rows = resolved["rowsBinding"]?.array {
        resolved["rows"] = .array(rows)
    }
    resolved["rowsBinding"] = nil
    return resolved
}

private func resolveWebLeafValue(_ value: PanelValue, state: PanelValue) -> PanelValue {
    switch value {
    case let .object(object):
        if object.count == 1, let path = object["$state"]?.string {
            return panelValue(at: path, in: state) ?? .null
        }
        return .object(object.mapValues { resolveWebLeafValue($0, state: state) })
    case let .array(values):
        return .array(values.map { resolveWebLeafValue($0, state: state) })
    default:
        return value
    }
}

#if os(macOS)
public struct PanelWebView: NSViewRepresentable {
    @ObservedObject var model: PanelWebModel
    let definition: [String: PanelValue]

    public init(model: PanelWebModel, definition: [String: PanelValue]) {
        self.model = model
        self.definition = definition
    }

        public func makeCoordinator() -> PanelWebCoordinator {
            PanelWebCoordinator(model: model, definition: definition)
        }

    public func makeNSView(context: Context) -> WKWebView {
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

    public func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.definition != definition { context.coordinator.mountSent = false }
        context.coordinator.definition = definition
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.scheduleMount()
    }
}
#else
public struct PanelWebView: UIViewRepresentable {
    @ObservedObject var model: PanelWebModel
    let definition: [String: PanelValue]

    public init(model: PanelWebModel, definition: [String: PanelValue]) {
        self.model = model
        self.definition = definition
    }

        public func makeCoordinator() -> PanelWebCoordinator {
            PanelWebCoordinator(model: model, definition: definition)
        }

    public func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(context: context)
        guard let url = URL(string: "hiboss-panel://panel/index.html") else { return webView }
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.definition != definition { context.coordinator.mountSent = false }
        context.coordinator.definition = definition
        context.coordinator.scheduleMount()
    }
}
#endif

#if os(iOS)
private extension PanelWebView {
    func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(PanelSchemeHandler(), forURLScheme: "hiboss-panel")
        configuration.userContentController.add(context.coordinator, name: "hiboss")
        let webView = DisplayWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        model.sendMessage = { [weak coordinator = context.coordinator] message in coordinator?.send(message) }
        return webView
    }
}
#endif
