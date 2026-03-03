#import "SceneDelegate.h"
#import "ViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    if (!windowScene) return;

    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    ViewController *rootVC = [[ViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:rootVC];
    self.window.rootViewController = navController;
    [self.window makeKeyAndVisible];

    NSURL *url = connectionOptions.URLContexts.anyObject.URL;
    if (url) {
        [rootVC handleDeepLink:url];
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    NSURL *url = URLContexts.anyObject.URL;
    if (!url) return;

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UINavigationController *nav = (UINavigationController *)windowScene.windows.firstObject.rootViewController;
    ViewController *vc = (ViewController *)nav.topViewController;
    if ([vc isKindOfClass:[ViewController class]]) {
        [vc handleDeepLink:url];
    }
}

@end
