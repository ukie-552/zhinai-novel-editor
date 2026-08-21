import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL
    var onCreated: ((WKWebView) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url))
        onCreated?(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
