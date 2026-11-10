import UIKit

/// 감시 스크립트가 보내는 `{ state, rect }`.
struct FloatingLayoutUpdate: Equatable {
    let isExpanded: Bool
    let touchableRect: CGRect

    init(isExpanded: Bool, touchableRect: CGRect) {
        self.isExpanded = isExpanded
        self.touchableRect = touchableRect
    }

    init?(body: Any) {
        guard let dict = body as? [String: Any] else { return nil }
        isExpanded = (dict["state"] as? String) == "expanded"
        if let rect = dict["rect"] as? [NSNumber], rect.count == 4 {
            touchableRect = CGRect(
                x: rect[0].doubleValue, y: rect[1].doubleValue,
                width: rect[2].doubleValue, height: rect[3].doubleValue
            )
        } else {
            touchableRect = .zero
        }
    }
}

/// 템플릿에 넘기는 위·아래 여백(`_marketap_native.topSafeArea`·`bottomSafeArea`).
struct FloatingInsets: Equatable {
    let top: CGFloat
    let bottom: CGFloat

    init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }

    init(safeArea: UIEdgeInsets) {
        self.init(top: safeArea.top, bottom: safeArea.bottom)
    }
}

enum FloatingDocument {
    static let layoutMessageName = "mktFloatingLayout"

    static func html(campaignHTML: String, insets: FloatingInsets, timerStartAt: Date) -> String {
        let handlers = MarketapJSMessage.allCases.map { $0.jsFunctionDefinition }.joined(separator: ",\n")
        let timerStartAtMillis = String(format: "%.0f", timerStartAt.timeIntervalSince1970 * 1000)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>html,body{margin:0;background:transparent}</style>
        <script>
        window._marketap_native = {
        \(handlers),
        topSafeArea: \(insets.top),
        bottomSafeArea: \(insets.bottom),
        timerStartAt: \(timerStartAtMillis)
        };
        </script>
        </head>
        <body>
        \(campaignHTML)
        <script>document.dispatchEvent(new Event("ForceDOMContentLoaded"));</script>
        <script>\(layoutWatcherScript)</script>
        </body>
        </html>
        """
    }

    static func applyInsetsScript(_ insets: FloatingInsets) -> String {
        """
        if (window._marketap_native) {
          window._marketap_native.topSafeArea = \(insets.top);
          window._marketap_native.bottomSafeArea = \(insets.bottom);
        }
        if (window.marketapApplySafeArea) { window.marketapApplySafeArea(); }
        """
    }

    static let layoutWatcherScript = """
    (function () {
      var observedWrapper = null;
      var observedVisible = null;
      function layoutRect(el) {
        var left = 0, top = 0;
        for (var n = el; n; n = n.offsetParent) { left += n.offsetLeft; top += n.offsetTop; }
        return [left, top, el.offsetWidth, el.offsetHeight];
      }
      function visibleElement() {
        return document.querySelector(".marketap-bar-row") || document.getElementById("marketap-content-container");
      }
      function post() {
        var wrapper = document.getElementById("marketap-content-wrapper");
        var state = wrapper ? wrapper.getAttribute("data-mkt-state") : null;
        var rect = null;
        var bar = document.querySelector(".marketap-bar-row");
        if (bar) {
          var b = bar.getBoundingClientRect();
          rect = [b.left, b.top, b.width, b.height];
        } else {
          var c = document.getElementById("marketap-content-container");
          if (c) rect = layoutRect(c);
        }
        window.webkit.messageHandlers.\(layoutMessageName).postMessage({ state: state, rect: rect });
      }
      function bind() {
        var wrapper = document.getElementById("marketap-content-wrapper");
        if (wrapper && wrapper !== observedWrapper) {
          observedWrapper = wrapper;
          new MutationObserver(post).observe(wrapper, { attributes: true, attributeFilter: ["data-mkt-state"] });
        }
        var visible = visibleElement();
        if (visible && visible !== observedVisible && window.ResizeObserver) {
          observedVisible = visible;
          new ResizeObserver(post).observe(visible);
        }
        post();
      }
      window.addEventListener("resize", post);
      document.addEventListener("transitionend", post, true);
      document.addEventListener("animationend", post, true);
      document.addEventListener("DOMContentLoaded", bind);
      window.addEventListener("load", bind);
      bind();
    })();
    """
}
