// Serves only the generated renderer files from the app's resource bundle.
// Exports: LocalSchemeHandler.
// Dependencies: WebKit, Foundation, and Bundle.module resource paths.

import Foundation
import WebKit

final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "hiboss-panel", url.host == "panel" else { urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return }
        let relativePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty, !relativePath.contains(".."), let root = Bundle.module.url(forResource: "Web", withExtension: nil), let fileURL = safeURL(relativePath, root: root), FileManager.default.fileExists(atPath: fileURL.path), let data = try? Data(contentsOf: fileURL) else { urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return }
        let response = URLResponse(url: url, mimeType: mimeType(for: fileURL.pathExtension), expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func safeURL(_ path: String, root: URL) -> URL? {
        let url = root.appendingPathComponent(path).standardizedFileURL
        return url.path.hasPrefix(root.standardizedFileURL.path + "/") ? url : nil
    }

    private func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() { case "html": return "text/html"; case "js": return "text/javascript"; case "css": return "text/css"; case "json": return "application/json"; default: return "application/octet-stream" }
    }
}
