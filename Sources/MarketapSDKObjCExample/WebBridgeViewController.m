#import "WebBridgeViewController.h"
#import <WebKit/WebKit.h>
@import MarketapSDK;

@interface WebBridgeViewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) MarketapWebBridge *webBridge;
@end

@implementation WebBridgeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Web Bridge";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *contentController = [[WKUserContentController alloc] init];

    [contentController addScriptMessageHandler:[[MarketapWebBridge alloc] initWithHandleInAppInWebView:YES] name:[MarketapWebBridge name]];
    configuration.userContentController = contentController;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.webView];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [self.webView loadHTMLString:[self demoHTML] baseURL:nil];
}

- (void)dealloc {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:[MarketapWebBridge name]];
}

- (NSString *)demoHTML {
    return @"<!doctype html>"
    "<html>"
    "<head>"
    "<meta name='viewport' content='width=device-width, initial-scale=1.0' />"
    "<style>"
    "body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px; background: #f6f7f9; color: #111827; }"
    "h1 { font-size: 28px; margin-bottom: 12px; }"
    "p { line-height: 1.5; color: #4b5563; }"
    "button { width: 100%; border: 0; border-radius: 12px; padding: 14px 16px; margin-top: 12px; background: #111827; color: white; font-size: 16px; }"
    ".secondary { background: #2563eb; }"
    ".card { background: white; border-radius: 16px; padding: 20px; box-shadow: 0 8px 24px rgba(17, 24, 39, 0.08); }"
    "</style>"
    "</head>"
    "<body>"
    "<div class='card'>"
    "<h1>Marketap Web Bridge Demo</h1>"
    "<p>Objective-C example registering <code>MarketapWebBridge</code> with <code>WKUserContentController</code>.</p>"
    "<button onclick='trackEvent()'>Send track event</button>"
    "<button class='secondary' onclick='identifyUser()'>Send identify</button>"
    "</div>"
    "<script>"
    "function postMessage(payload) {"
    "  window.webkit.messageHandlers.marketap.postMessage(payload);"
    "}"
    "function trackEvent() {"
    "  postMessage({"
    "    type: 'track',"
    "    params: {"
    "      eventName: 'objc_webbridge_event',"
    "      eventProperties: {"
    "        source: 'objc_example_webview',"
    "        screen: 'web_bridge_demo'"
    "      }"
    "    }"
    "  });"
    "}"
    "function identifyUser() {"
    "  postMessage({"
    "    type: 'identify',"
    "    params: {"
    "      userId: 'objc-web-user',"
    "      userProperties: {"
    "        mkt_name: 'ObjC Web User',"
    "        mkt_email: 'objc-web@example.com'"
    "      }"
    "    }"
    "  });"
    "}"
    "</script>"
    "</body>"
    "</html>";
}

@end
