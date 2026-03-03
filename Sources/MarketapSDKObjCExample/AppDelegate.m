#import "AppDelegate.h"
@import MarketapSDK;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;

    [Marketap setLogLevelRaw:0]; // verbose
    [Marketap initializeWithProjectId:@"kx43pz7"];
    [Marketap setClickHandlerObjC:^(MarketapClickEventObjC * _Nonnull event) {
        NSString *urlString = (NSString *)event.url;
        if (urlString) {
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                });
            }
        }
    }];
    [Marketap application:application didFinishLaunchingWithOptions:launchOptions];
    [Marketap requestAuthorizationForPushNotifications];

    NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:@"userName"];
    NSString *email = [[NSUserDefaults standardUserDefaults] stringForKey:@"userEmail"];
    NSString *phone = [[NSUserDefaults standardUserDefaults] stringForKey:@"userPhone"];

    if (name && email && phone) {
        [Marketap identifyWithUserId:phone userProperties:@{
            @"mkt_name": name,
            @"mkt_email": email,
            @"mkt_phone_number": phone
        }];
    }

    return YES;
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    [Marketap setPushTokenWithToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"Failed to register for remote notifications: %@", error.localizedDescription);
}

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    if ([Marketap userNotificationCenter:center willPresent:notification withCompletionHandler:completionHandler]) {
        return;
    }
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    if ([Marketap userNotificationCenter:center didReceive:response withCompletionHandler:completionHandler]) {
        return;
    }
    completionHandler();
}

@end
