// Serves only the generated renderer files from the seam app's resource bundle.
// Exports: LocalSchemeHandler.
// Dependencies: WebKit, Foundation, and Bundle.module resources.

import Foundation
import WebKit

final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "hiboss-panel", url.host == "panel" else { urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty, !path.contains(".."), let root = Bundle.module.url(forResource: "Web", withExtension: nil) else { urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return }
        let fileURL = root.appendingPathComponent(path).standardizedFileURL
        guard fileURL.path.hasPrefix(root.standardizedFileURL.path + "/"), let data = try? Data(contentsOf: fileURL) else { urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return }
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mimeType(for: fileURL.pathExtension), expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() { case "html": return "text/html"; case "js": return "text/javascript"; case "css": return "text/css"; default: return "application/octet-stream" }
    }
}
