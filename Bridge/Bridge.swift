import Foundation
import WebKit

/// Receives messages posted by feed-observer.js via window.webkit.messageHandlers.tq.
/// Holds callbacks weakly-decoupled from the web view so FeedView stays simple.
final class Bridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "tq"

    var onVideo: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Bridge.handlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "video":
            if let id = body["id"] as? String, !id.isEmpty {
                onVideo?(id)
            }
        case "log":
            onLog?(body["msg"] as? String ?? "")
        default:
            onLog?("unknown message type: \(type)")
        }
    }

    /// Builds the injected user script: feed-observer.js with hide selectors spliced in.
    static func makeUserScript(hideSelectors: [String]) -> WKUserScript {
        let js = loadObserverJS()
        let selectorsJSON: String
        if let data = try? JSONEncoder().encode(hideSelectors), let s = String(data: data, encoding: .utf8) {
            selectorsJSON = s
        } else {
            selectorsJSON = "[]"
        }
        let source = js.replacingOccurrences(of: "__HIDE_SELECTORS__", with: selectorsJSON)
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private static func loadObserverJS() -> String {
        guard let url = Bundle.main.url(forResource: "feed-observer", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("feed-observer.js missing from bundle")
            return ""
        }
        return s
    }
}
