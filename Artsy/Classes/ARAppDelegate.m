#ifdef STORE
#define ADMIN_MENU_ENABLED 0
#else
#define ADMIN_MENU_ENABLED 1
#endif

#import <ORKeyboardReactingApplication/ORKeyboardReactingApplication.h>
#import <iRate/iRate.h>
#import <AFOAuth1Client/AFOAuth1Client.h>
#import <ARAnalytics/ARAnalytics.h>
#import "ARAnalyticsConstants.h"

#import "ARAppDelegate.h"
#import "ARAppDelegate+Analytics.h"
#import "ARUserManager.h"

#import "ARAdminSettingsViewController.h"
#import "ARQuicksilverViewController.h"
#import "ARRouter.h"
#import "UIViewController+ARStateRestoration.h"
#import "ARNetworkConstants.h"
#import "ArtsyAPI+Private.h"
#import "ARFileUtils.h"
#import "FBSettings.h"
#import "FBAppCall.h"
#import <CocoaPods-Keys/ArtsyKeys.h>

#if ADMIN_MENU_ENABLED
#import <DHCShakeNotifier/UIWindow+DHCShakeRecognizer.h>
#import <VCRURLConnection/VCR.h>
#endif

// demo
#import "ARDemoSplashViewController.h"
#import "ARShowFeedViewController.h"

// Artisan Added
#import <ArtisanSDK/ArtisanSDK.h>

#import "ArtisanEnvironments.h"
#import "ArtisanArtsyConstants.h"


@interface ARAppDelegate()
@property (strong, nonatomic, readwrite) NSString *referralURLRepresentation;
@property (strong, nonatomic, readwrite) NSString *landingURLRepresentation;
@end

@implementation ARAppDelegate

static ARAppDelegate *_sharedInstance = nil;

+ (void)load
{
    id delegate = [[self alloc] init];
    [JSDecoupledAppDelegate sharedAppDelegate].appStateDelegate = delegate;
    [JSDecoupledAppDelegate sharedAppDelegate].URLResourceOpeningDelegate = delegate;
}

+ (ARAppDelegate *)sharedInstance
{
    return _sharedInstance;
}

// These methods are swizzled during unit tests. See ARAppDelegate(Testing).

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // NOTE: This needs to be called here since I'm using a default PH value in the ARTopMenuViewController#viewDidLoad method
    [self registerArtisanPowerHooks];
    
    _sharedInstance = self;

    if (ARIsRunningInDemoMode) {
        [self resetUserDefaults];
    }

    [ARDefaults setup];
    [ARRouter setup];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.viewController = [ARTopMenuViewController sharedController];

    [self.viewController setupRestorationIdentifierAndClass];

    [self setupAdminTools];

    [self setupAnalytics];
    [self setupRatingTool];
    [self countNumberOfRuns];

    self.window.rootViewController = self.viewController;

    [self.window makeKeyAndVisible];

    return YES;
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    _landingURLRepresentation = self.landingURLRepresentation ?: @"http://artsy.net";

    [[ARTLogger sharedLogger] startLogging];
    [FBSettings setDefaultAppID:[ArtsyKeys new].artsyFacebookAppID];

    if (ARIsRunningInDemoMode) {

        [self.viewController presentViewController:[[ARDemoSplashViewController alloc] init] animated:NO completion:nil];
        [self performSelector:@selector(finishDemoSplash) withObject:nil afterDelay:1];

    } else if(![[ARUserManager sharedManager] hasExistingAccount]) {

        [self fetchSiteFeatures];
        [self showTrialOnboardingWithState:ARInitialOnboardingStateSlideShow andContext:ARTrialContextNotTrial];
    }

    ARShowFeedViewController *topVC = (id)ARTopMenuViewController.sharedController.rootNavigationController.topViewController;
    [ArtsyAPI getXappTokenWithCompletion:^(NSString *xappToken, NSDate *expirationDate) {

        // Sync clock with server
        [ARSystemTime sync];

        // Start doing the network calls to grab the feed
        [topVC refreshFeedItems];

    }];
    
    
      ///////////////////
     // Artisan Start //
    ///////////////////
    
    // In-Code Experiment Registration
    ///////////////////////////////////

    [ARExperimentManager registerExperiment:SearchInfoTextInCodeExperimentName description:@"Testing the text of the search page"];
    [ARExperimentManager addVariant:SearchInfoTextDefaultVariationName forExperiment:SearchInfoTextInCodeExperimentName isDefault:YES];
    [ARExperimentManager addVariant:SearchInfoAllTheThingsVariationName forExperiment:SearchInfoTextInCodeExperimentName];
    
    // Configuration
    /////////////////
    
    ArtisanEnvironmentConfigurationModel *environmentConfiguration = [[ArtisanEnvironmentConfigurationModel alloc] init];
    //environmentConfiguration.debugLogging = YES;
    environmentConfiguration.prettyJSON = YES;
    // environmentConfiguration.echoAnalytics = YES;
    environmentConfiguration.echoPlaylists = YES;
    // environmentConfiguration.alwaysEnableGesture = YES;
    // environmentConfiguration.overrideIPAddress = @"http://10.1.10.31:3000";
    
    NSString *appId = @"5502f8a47d891c6fd1000001";
    
    // Local
    // [ARManager startWithAppId:[[ADAppIDModel sharedModel] getCurrentAppID] options:[ArtisanEnvironments optionsForLocalEnvironmentWithConfiguration:environmentConfiguration]];
    
    // QA3
    [ARManager startWithAppId:appId options:[ArtisanEnvironments optionsForQA3EnvironmentWithConfiguration:environmentConfiguration]];
    
    // Production
    // [ARManager startWithAppId:[[ADAppIDModel sharedModel] getCurrentAppID] options:[ArtisanEnvironments optionsForLocalEnvironmentWithConfiguration:environmentConfiguration]];

    return YES;
}

- (void)registerArtisanPowerHooks {
    // Power Hook Registration
    ///////////////////////////
    
    [ARPowerHookManager registerHookWithId:YouTabTextPowerHookId friendlyName:@"Text for the 'You' Tab" defaultValue:@"You"];
    [ARPowerHookManager registerHookWithId:DefaultSearchTextPowerHookId friendlyName:@"The default search text for the search area" defaultValue:@""];
    [ARPowerHookManager registerHookWithId:SelectedFavoritesTabPowerHookId friendlyName:@"The selected 'tab' you see when you navigate to the 'You' tab" defaultValue:@"ARTWORKS"];
    
    [ARPowerHookManager registerBlockWithId:ShowAlertWithTextBlockPowerHookId
                               friendlyName:@"Show a Pop Up Alert with the given text"
                                       data:@{ @"header": @"Default Header", @"body": @"Default Body" }
                                   andBlock:^(NSDictionary *extra_data, id context) {
                                       NSString *header = [extra_data objectForKey:@"header"];
                                       NSString *body   = [extra_data objectForKey:@"body"];
                                       
                                       UIAlertView *alert = [[UIAlertView alloc] initWithTitle:header
                                                                                       message:body
                                                                                      delegate:nil
                                                                             cancelButtonTitle:@"OK"
                                                                             otherButtonTitles:nil];
                                       [alert show];
                                   }];

}

- (void)finishDemoSplash
{
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)finishOnboardingAnimated:(BOOL)animated
{
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    [[ARTopMenuViewController sharedController] moveToInAppAnimated:animated];
}

- (void)showTrialOnboardingWithState:(enum ARInitialOnboardingState)state andContext:(enum ARTrialContext)context
{
    AROnboardingViewController *onboardVC = [[AROnboardingViewController alloc] initWithState:state];
    onboardVC.trialContext = context;
    onboardVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self.viewController presentViewController:onboardVC animated:NO completion:nil];
}

- (void)setupAdminTools
{
#if ADMIN_MENU_ENABLED

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rageShakeNotificationRecieved) name:DHCSHakeNotificationName object:nil];

    if ([AROptions boolForOption:AROptionsUseVCR]) {
        NSURL *url = [NSURL fileURLWithPath:[ARFileUtils cachesPathWithFolder:@"vcr" filename:@"eigen.json"]];
        [VCR loadCassetteWithContentsOfURL:url];
        [VCR start];
    }

    [ORKeyboardReactingApplication registerForCallbackOnKeyDown:ORTildeKey :^{
        [self rageShakeNotificationRecieved];
    }];

    [ORKeyboardReactingApplication registerForCallbackOnKeyDown:ORSpaceKey :^{
        [self showQuicksilver];
    }];

    [ORKeyboardReactingApplication registerForCallbackOnKeyDown:ORDeleteKey :^{
        [ARTopMenuViewController.sharedController.rootNavigationController popViewControllerAnimated:YES];
    }];

#endif
}

- (void)setupRatingTool
{
    [iRate sharedInstance].promptForNewVersionIfUserRated = NO;
    [iRate sharedInstance].verboseLogging = NO;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
    _referralURLRepresentation = sourceApplication;
    _landingURLRepresentation = [url absoluteString];

    // Twitter SSO
    NSString *fbScheme = [@"fb" stringByAppendingString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"FacebookAppID"]];
    if ([[url absoluteString] hasPrefix:ARTwitterCallbackPath]) {
        NSNotification *notification = nil;
        notification = [NSNotification notificationWithName:kAFApplicationLaunchedWithURLNotification
                                                     object:nil
                                                   userInfo:@{ kAFApplicationLaunchOptionsURLKey:url }];

        [[NSNotificationCenter defaultCenter] postNotification:notification];
        return YES;

    // Facebook
    } else if ([[url scheme] isEqualToString:fbScheme]) {
        // Call FBAppCall's handleOpenURL:sourceApplication to handle Facebook app responses
        BOOL wasHandled = [FBAppCall handleOpenURL:url sourceApplication:sourceApplication];

        // You can add your app-specific url handling code here if needed

        return wasHandled;
    } else if ([url isFileURL]) {
        // AirDrop receipt
        NSData *fileData = [NSData dataWithContentsOfURL:url];
        NSDictionary *data = [NSJSONSerialization JSONObjectWithData:fileData options:0 error:nil];
        NSString *urlString = [data valueForKey:@"url"];

        if (urlString) {
            _landingURLRepresentation = urlString;

            UIViewController *viewController = [ARSwitchBoard.sharedInstance loadURL:[NSURL URLWithString:urlString]];
            if (viewController) {
                [[ARTopMenuViewController sharedController] pushViewController:viewController];
            }
        }
    } else {
        UIViewController *viewController = [ARSwitchBoard.sharedInstance loadURL:url];
        if (viewController) {
            [[ARTopMenuViewController sharedController] pushViewController:viewController];
        }
    }

    return YES;

}

- (void)rageShakeNotificationRecieved
{
    UINavigationController *navigationController = ARTopMenuViewController.sharedController.rootNavigationController;

    if (![navigationController.topViewController isKindOfClass:ARAdminSettingsViewController.class]) {
        ARAdminSettingsViewController *adminSettings = [[ARAdminSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
        [navigationController pushViewController:adminSettings animated:YES];
    }
}

- (void)showQuicksilver
{
    UINavigationController *navigationController = ARTopMenuViewController.sharedController.rootNavigationController;

    // As this is hooked up to return everywhere, it shouldn't be able to
    // call itself when it's just finished showing
    NSInteger count = navigationController.viewControllers.count;

    if (count > 1) {
        id oldVC = navigationController.viewControllers[count -2];
        if ([oldVC isKindOfClass:[ARQuicksilverViewController class]]) {
            return;
        }
    }

    ARQuicksilverViewController *adminSettings = [[ARQuicksilverViewController alloc] init];
    [navigationController pushViewController:adminSettings animated:YES];

}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [ARTrialController extendTrial];
    [ARAnalytics startTimingEvent:ARAnalyticsTimePerSession];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    [ARAnalytics finishTimingEvent:ARAnalyticsTimePerSession];
}

- (void)fetchSiteFeatures
{
    [ArtsyAPI getXappTokenWithCompletion:^(NSString *xappToken, NSDate *expirationDate) {
       [ArtsyAPI getSiteFeatures:^(NSArray *features) {
           [ARDefaults setOnboardingDefaults:features];

       } failure:^(NSError *error) {
           //ARTErrorLog(@"Couldn't get site features. Error %@", error.localizedDescription);
       }];
    }];
}

-(void)countNumberOfRuns
{
    NSInteger numberOfRuns = [[NSUserDefaults standardUserDefaults] integerForKey:ARAnalyticsAppUsageCountProperty] + 1;
    if (numberOfRuns == 1) {
        [ARAnalytics event:ARAnalyticsFreshInstall];
    }

    [[NSUserDefaults standardUserDefaults] setInteger:numberOfRuns forKey:ARAnalyticsAppUsageCountProperty];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)resetUserDefaults
{
    [[ARUserManager sharedManager] logout];
}

@end
