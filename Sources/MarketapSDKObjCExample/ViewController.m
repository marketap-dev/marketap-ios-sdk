#import "ViewController.h"
@import MarketapSDK;

typedef NS_ENUM(NSInteger, ExampleSection) {
    ExampleSectionTracking = 0,
    ExampleSectionUser,
    ExampleSectionCount
};

@interface ViewController ()
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *menuItems;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MarketapSDK ObjC Example";

    self.sectionTitles = @[@"Event Tracking", @"User"];

    self.menuItems = @[
        @[@"Track Event", @"Track Purchase", @"Track Page View", @"Track Revenue"],
        @[@"Identify", @"Login", @"Signup", @"Logout", @"Reset Identity"]
    ];

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];

    [Marketap trackPageViewWithEventProperties:@{@"mkt_page_title": @"Home"}];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return ExampleSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.menuItems[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sectionTitles[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.textLabel.text = self.menuItems[indexPath.section][indexPath.row];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case ExampleSectionTracking:
            [self handleTrackingAction:indexPath.row];
            break;
        case ExampleSectionUser:
            [self handleUserAction:indexPath.row];
            break;
    }
}

#pragma mark - Tracking Actions

- (void)handleTrackingAction:(NSInteger)row {
    switch (row) {
        case 0: // Track Event
            [Marketap trackWithEventName:@"objc_test_event" eventProperties:@{
                @"source": @"objc_example",
                @"timestamp": @([[NSDate date] timeIntervalSince1970])
            }];
            [self showAlert:@"Track Event" message:@"objc_test_event sent"];
            break;

        case 1: // Track Purchase
            [Marketap trackPurchaseWithRevenue:29900 eventProperties:@{
                @"mkt_product_id": @"PROD_001",
                @"mkt_product_name": @"Test Product",
                @"mkt_product_price": @(29900),
                @"mkt_quantity": @(1),
                @"mkt_category1": @"Test"
            }];
            [self showAlert:@"Track Purchase" message:@"Purchase event sent (29,900)"];
            break;

        case 2: // Track Page View
            [Marketap trackPageViewWithEventProperties:@{@"mkt_page_title": @"ObjC Example Page"}];
            [self showAlert:@"Track Page View" message:@"Page view event sent"];
            break;

        case 3: // Track Revenue
            [Marketap trackRevenueWithEventName:@"subscription_start" revenue:9900 eventProperties:@{
                @"plan": @"premium"
            }];
            [self showAlert:@"Track Revenue" message:@"Revenue event sent (9,900)"];
            break;
    }
}

#pragma mark - User Actions

- (void)handleUserAction:(NSInteger)row {
    switch (row) {
        case 0: // Identify
            [self showIdentifyDialog];
            break;

        case 1: // Login
            [self showLoginDialog];
            break;

        case 2: // Signup
            [self showSignupDialog];
            break;

        case 3: // Logout
            [Marketap logoutWithEventProperties:nil];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"userName"];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"userEmail"];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"userPhone"];
            [self showAlert:@"Logout" message:@"User logged out"];
            break;

        case 4: // Reset Identity
            [Marketap resetIdentity];
            [self showAlert:@"Reset Identity" message:@"Identity has been reset"];
            break;
    }
}

#pragma mark - Dialogs

- (void)showIdentifyDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Identify"
                                                                  message:@"Enter user info"
                                                           preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"User ID (phone)"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Name"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Email"; tf.keyboardType = UIKeyboardTypeEmailAddress; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Identify" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *userId = alert.textFields[0].text;
        NSString *name = alert.textFields[1].text;
        NSString *email = alert.textFields[2].text;

        if (userId.length == 0) return;

        NSMutableDictionary *props = [NSMutableDictionary dictionary];
        if (name.length > 0) props[@"mkt_name"] = name;
        if (email.length > 0) props[@"mkt_email"] = email;
        props[@"mkt_phone_number"] = userId;

        [Marketap identifyWithUserId:userId userProperties:props];

        [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"userName"];
        [[NSUserDefaults standardUserDefaults] setObject:email forKey:@"userEmail"];
        [[NSUserDefaults standardUserDefaults] setObject:userId forKey:@"userPhone"];

        [self showAlert:@"Identify" message:[NSString stringWithFormat:@"Identified as %@", userId]];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showLoginDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Login"
                                                                  message:@"Enter user ID"
                                                           preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"User ID"; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Login" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *userId = alert.textFields[0].text;
        if (userId.length == 0) return;

        [Marketap loginWithUserId:userId userProperties:nil eventProperties:nil];
        [[NSUserDefaults standardUserDefaults] setObject:userId forKey:@"userPhone"];

        [self showAlert:@"Login" message:[NSString stringWithFormat:@"Logged in as %@", userId]];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSignupDialog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Signup"
                                                                  message:@"Enter user info"
                                                           preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"User ID (phone)"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Name"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Email"; tf.keyboardType = UIKeyboardTypeEmailAddress; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Signup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *userId = alert.textFields[0].text;
        NSString *name = alert.textFields[1].text;
        NSString *email = alert.textFields[2].text;

        if (userId.length == 0) return;

        NSMutableDictionary *userProps = [NSMutableDictionary dictionary];
        if (name.length > 0) userProps[@"mkt_name"] = name;
        if (email.length > 0) userProps[@"mkt_email"] = email;
        userProps[@"mkt_phone_number"] = userId;

        [Marketap signupWithUserId:userId userProperties:userProps eventProperties:nil persistUser:YES];

        [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"userName"];
        [[NSUserDefaults standardUserDefaults] setObject:email forKey:@"userEmail"];
        [[NSUserDefaults standardUserDefaults] setObject:userId forKey:@"userPhone"];

        [self showAlert:@"Signup" message:[NSString stringWithFormat:@"Signed up as %@", userId]];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Deep Link

- (void)handleDeepLink:(NSURL *)url {
    NSString *host = url.host;
    if (!host) return;

    if ([host isEqualToString:@"track"]) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *eventName = nil;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"event"]) {
                eventName = item.value;
                break;
            }
        }
        if (eventName) {
            [Marketap trackWithEventName:eventName eventProperties:@{@"source": @"deeplink"}];
            [self showAlert:@"Deep Link" message:[NSString stringWithFormat:@"Tracked: %@", eventName]];
        }
    } else if ([host isEqualToString:@"identify"]) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString *userId = nil;
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqualToString:@"user_id"]) {
                userId = item.value;
                break;
            }
        }
        if (userId) {
            [Marketap identifyWithUserId:userId userProperties:nil];
            [self showAlert:@"Deep Link" message:[NSString stringWithFormat:@"Identified: %@", userId]];
        }
    }
}

#pragma mark - Utility

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
