#import "ARViewInRoomViewController.h"
#import "ARFeedImageLoader.h"

// Artisan Added
#import <ArtisanSDK/ArtisanSDK.h>
#import "ArtisanArtsyConstants.h"

#define DEBUG_VIEW_IN_ROOM 0

static const CGFloat InitialWidthOfBenchInches = 96;
static const CGFloat InitialWidthOfBenchPX = 220;
static const CGFloat InitialWidthOfBenchPXLandscape = 150;

// The minimum distance is the closest point the artwork can come to the ground,
// from there it will scale upwards with the bottom aligned to this line
static const CGFloat ArtworkMinDistanceToBench = 70;

// How much do we pull the BG down by for Landscope
static const CGFloat LandscapeOrientationBackgroundNegativeBottomMargin = 33;
static const CGFloat LandscapeOrientationArtworkNegativeBottomMargin = 80;

// The Eyeline level is the point at which we will vertically center the artwork
// unless it's too tall that it touches the minimum distance above
static const CGFloat ArtworkEyelineLevelFromBench = 160;

static const CGFloat DistanceToTopOfBenchPortrait =  90;

@interface ARViewInRoomViewController ()

@property (nonatomic, strong) Artwork *artwork;
@property (nonatomic, assign) CGFloat zoomScale;

@property (nonatomic, assign) NSInteger roomSize;
@property (nonatomic, weak) UIImageView *backgroundImageView;

// For parallax horizontal VIR
@property (nonatomic, weak) UIImageView *chairImageView;
@property (nonatomic, weak) UIImageView *leftWallImageView;
@property (nonatomic, weak) UIImageView *rightWallImageView;
@property (nonatomic, weak) UIImageView *dudeImageView;


// Debug information
@property (nonatomic, weak) UILabel *debugSizeLabel;
@property (nonatomic, weak) UIView *debugMinimumArtworkView;
@property (nonatomic, weak) UIView *debugEyelineView;

@property (readwrite, nonatomic, assign) BOOL hidesBackButton;

@end

@implementation ARViewInRoomViewController

+ (UIImageView *)imageViewForFramedArtwork
{
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    imageView.contentMode = UIViewContentModeScaleAspectFit;

    // Add a shadow to the artwork image
    CALayer *layer = [imageView layer];
    layer.shadowOffset = CGSizeMake(0, 4);
    layer.shadowOpacity = 0;
    layer.shadowColor = [[UIColor blackColor] CGColor];

    return imageView;
}

- (ARViewInRoomViewController *)initWithArtwork:(Artwork *)artwork
{
    self = [super init];
    if (!self) { return nil; }

    _artwork = artwork;
    self.view.clipsToBounds = YES;

    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    self.hidesBackButton = UIInterfaceOrientationIsLandscape(orientation);

    return self;
}

#pragma mark - ARMenuAwareViewController

- (BOOL)hidesToolbarMenu {
    return YES;
}

#pragma mark - UIViewController

- (void)viewDidAppear:(BOOL)animated
{
    // When not in an ARNavgiationController
    if (!self.artworkImageView) {
        self.artworkImageView = [ARViewInRoomViewController imageViewForFramedArtwork];
        self.artworkImageView.frame = [ARViewInRoomViewController rectForImageViewWithArtwork:self.artwork withContainerFrame:self.view.bounds];

        [[ARFeedImageLoader alloc] loadImageAtAddress:[self.artwork baseImageURL] desiredSize:ARFeedItemImageSizeLarge
                                         forImageView:self.artworkImageView customPlaceholder:nil];

        self.artworkImageView.layer.shadowOpacity = 0.3;
    }
    
    [ARPowerHookManager executeBlockWithId:ShowAlertWithTextBlockPowerHookId data:@{} context:self];

    [super viewDidAppear:animated];
}

- (void)loadView
{
    UIImageView *galleryBackground = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ViewInRoom_Base"]];
    self.backgroundImageView = galleryBackground;
    self.backgroundImageView.contentMode = UIViewContentModeBottom;
    self.backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [super loadView];

    self.view.backgroundColor = [UIColor colorWithHex:0xfcfbfa];

    [self.view addSubview:galleryBackground];

    #if DEBUG_VIEW_IN_ROOM
        [self setupDebugTools];
    #endif
}

- (void)setArtworkImageView:(UIImageView *)artworkImageView {
    _artworkImageView = artworkImageView;
    self.artworkImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.artworkImageView.backgroundColor = [UIColor clearColor];

    if (self.chairImageView) {
        [self.view insertSubview:self.artworkImageView belowSubview:self.chairImageView];
    } else {
        [self.view addSubview:self.artworkImageView];
    }

    UITapGestureRecognizer *exitTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self.navigationController action:@selector(popViewControllerAnimated:)];
    self.artworkImageView.userInteractionEnabled = YES;
    [self.artworkImageView addGestureRecognizer:exitTapGesture];

}

- (void)tappedArtwork {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillLayoutSubviews
{
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);

    if (isLandscape) {
        self.backgroundImageView.image = [UIImage imageNamed:@"ViewInRoom_BaseNoBench"];
        [self setupParallaxVIR];

        CGRect backgroundFrame = self.view.bounds;
        backgroundFrame.origin.y += LandscapeOrientationBackgroundNegativeBottomMargin;
        self.backgroundImageView.frame = backgroundFrame;

    } else {
        [self hideDecorationViews];
        self.backgroundImageView.image = [UIImage imageNamed:@"ViewInRoom_Base"];
        self.backgroundImageView.frame = self.view.frame;
    }

    if (self.artworkImageView) {
        self.artworkImageView.frame = [self.class rectForImageViewWithArtwork:self.artwork withContainerFrame:self.view.bounds];
    }

#if DEBUG_VIEW_IN_ROOM
    [self updateDebugViews];
#endif
}


- (void)setupParallaxVIR {
    CGFloat wallsWidth = 90;
    CGFloat wallsYOffset = -2;
    CGFloat wallsStretch = 8;

    CGFloat chairHeight = 50;
    CGFloat chairWidth = 160;
    CGFloat chairOffset = 70;

    CGFloat dudeCenterXOffset = -130;
    CGFloat dudeYOffset = -10;

    // Current aspect ratio = 3.(1/3)
    CGFloat dudeHeight = 160;
    CGFloat dudeWidth = 48;

    CGFloat chairMotionDelta = 24;
    CGFloat dudeMotionDelta = 5;
    CGFloat wallMotionDelta = 200;
    CGFloat artworkMotionDelta = 50;

    self.artworkImageView.userInteractionEnabled = NO;

    self.hidesBackButton = YES;

    if (self.artworkImageView && self.artworkImageView.motionEffects.count == 0) {
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedArtwork)];
        [self.artworkImageView addGestureRecognizer:tapGesture];

        UIInterpolatingMotionEffect *artworkMotion = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x"
                                                                                                     type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        artworkMotion.minimumRelativeValue = @(artworkMotionDelta);
        artworkMotion.maximumRelativeValue = @(-artworkMotionDelta);
        [self.artworkImageView addMotionEffect:artworkMotion];
    }

    if (!self.chairImageView) {
        UIImageView *chairView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ViewInRoom_Bench"]];
        chairView.contentScaleFactor = UIViewContentModeScaleAspectFill;
        self.chairImageView = chairView;

        CGRect chairFrame = CGRectMake(CGRectGetWidth(self.view.bounds)/2 - chairWidth/2, CGRectGetHeight(self.view.bounds) - chairOffset, chairWidth, chairHeight);
        chairView.frame = chairFrame;

        [self.view addSubview:chairView];

        UIInterpolatingMotionEffect *chairMotion = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x"
                                                        type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        chairMotion.minimumRelativeValue = @(chairMotionDelta);
        chairMotion.maximumRelativeValue = @(-chairMotionDelta);
        [self.chairImageView addMotionEffect:chairMotion];
    }

    if (!self.leftWallImageView) {
        UIImageView *leftWallView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ViewInRoom_Wall"]];
        self.leftWallImageView = leftWallView;
        leftWallView.contentScaleFactor = UIViewContentModeScaleAspectFit;

        leftWallView.frame = CGRectMake(0, wallsYOffset, wallsWidth, CGRectGetHeight(self.view.bounds) + wallsStretch);
        [self.view addSubview:leftWallView];

        UIInterpolatingMotionEffect *wallMotion = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"bounds"
                                                                                                  type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        wallMotion.minimumRelativeValue = [NSValue valueWithCGRect:CGRectMake(0, 0, -wallMotionDelta, 0)];
        wallMotion.maximumRelativeValue = [NSValue valueWithCGRect:CGRectMake(0, 0, 0, 0)];
        [leftWallView addMotionEffect:wallMotion];
    }

    if (!self.rightWallImageView) {
        UIImageView *rightWallView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ViewInRoom_Wall_Right"]];
        self.rightWallImageView = rightWallView;
        rightWallView.contentScaleFactor = UIViewContentModeScaleAspectFit;
        rightWallView.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - wallsWidth, wallsYOffset, wallsWidth, CGRectGetHeight(self.view.bounds) + wallsStretch);

        [self.view addSubview:rightWallView];

        UIInterpolatingMotionEffect *chairMotion = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x"
                                                                                                   type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        chairMotion.minimumRelativeValue = @(-7);
        chairMotion.maximumRelativeValue = @(7);
        [rightWallView addMotionEffect:chairMotion];


        UIInterpolatingMotionEffect *wallMotion = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"bounds"
                                                                                                  type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        wallMotion.minimumRelativeValue = [NSValue valueWithCGRect:CGRectMake(0, 0, 0, 0)];
        wallMotion.maximumRelativeValue = [NSValue valueWithCGRect:CGRectMake(0, 0, wallMotionDelta, 0)];
        [rightWallView addMotionEffect:wallMotion];
    }

    if (!self.dudeImageView) {
        UIImageView *dudeView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ViewInRoom_Man_3"]];
        self.dudeImageView = dudeView;
        dudeView.contentScaleFactor = UIViewContentModeScaleAspectFit;
        dudeView.frame = CGRectMake(CGRectGetWidth(self.view.bounds)/2 + dudeCenterXOffset, CGRectGetHeight(self.view.bounds) - dudeHeight + dudeYOffset, dudeWidth, dudeHeight);
        [self.view addSubview:dudeView];

        UIInterpolatingMotionEffect *chairMotion = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x"
                                                                                                   type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        chairMotion.minimumRelativeValue = @(dudeMotionDelta);
        chairMotion.maximumRelativeValue = @(-dudeMotionDelta);
        [self.dudeImageView addMotionEffect:chairMotion];
    }

}

- (void)hideDecorationViews {
    if (!self.artworkImageView || !self.leftWallImageView || !self.rightWallImageView) {
        return;
    }

    self.artworkImageView.userInteractionEnabled = YES;

    self.hidesBackButton = NO;

    NSArray *effects = self.artworkImageView.motionEffects.copy;
    for (UIMotionEffect *effect in effects) {
        [self.artworkImageView removeMotionEffect:effect];
    }

    NSArray *views = @[self.chairImageView, self.leftWallImageView, self.rightWallImageView];
    for (__strong UIView *decorationView in views) {
        [decorationView removeFromSuperview];
        decorationView = nil;
    }

    if (self.dudeImageView) {
        [self.dudeImageView removeFromSuperview];
        self.dudeImageView = nil;
    }
}

+ (CGRect)rectForImageViewWithArtwork:(Artwork *)artwork withContainerFrame:(CGRect)containerFrame
{
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    CGFloat benchWidth = isLandscape? InitialWidthOfBenchPXLandscape : InitialWidthOfBenchPX;

    // Initial Scale in this case is when the image is at 100% zoom
    CGFloat initialScale =  benchWidth / InitialWidthOfBenchInches;
    CGFloat artworkWidth = artwork.widthInches;
    CGFloat scale = initialScale;

    if (artworkWidth > InitialWidthOfBenchInches) {
        // we have MaximumWidthOfArtworkPX as the horizontal bounds
        //        CGFloat pixelsPerInch = artworkWidth / MaximumWidthOfArtworkPX;

        // Generate the new background width
        //        CGFloat newBackgroundImageWidth =  (CGRectGetWidth(self.backgroundImageView.frame) / initialScale) * pixelsPerInch;

    }

    CGFloat artworkHeight = artwork.heightInches;
    CGFloat artworkDiameter = artwork.diameterInches;

    CGFloat scaledWidth;
    CGFloat scaledHeight;

    if (artworkDiameter > 0) {
        scaledWidth = scaledHeight = floorf(artworkDiameter * scale);
    } else {
        scaledWidth = floorf(artworkWidth * scale);
        scaledHeight = floorf(artworkHeight * scale);
    }

    CGRect frame = {
        .origin = {
            floorf((CGRectGetWidth(containerFrame) - scaledWidth)  * .5f),
            floorf(CGRectGetHeight(containerFrame) - [self artworkEyelineLevel] - (scaledHeight * .5f))
        },
        .size = {
            scaledWidth,
            scaledHeight
        },
    };

    if (frame.origin.y < 0 || [self artworkFrameIsBelowMinimumDistance:frame inContainer:containerFrame]) {
        frame.origin.y = CGRectGetHeight(containerFrame) - [self artworkMinimumDistanceToBottom] - scaledHeight;
    }

    // HACK for VIR landscape artwork Y adjustments ./
    if (isLandscape) {
        frame.origin.y += LandscapeOrientationArtworkNegativeBottomMargin;
    }

    return frame;
}

+ (BOOL)artworkFrameIsBelowMinimumDistance:(CGRect)artworkFrame inContainer:(CGRect) containerFrame
{
    return (CGRectGetMaxY(artworkFrame) > CGRectGetHeight(containerFrame) - [self artworkMinimumDistanceToBottom]);
}

+ (CGFloat)artworkMinimumDistanceToBottom
{
    return [self distanceToTopOfBench] + ArtworkMinDistanceToBench;
}

+ (CGFloat)artworkEyelineLevel
{
    return  [self distanceToTopOfBench] + ArtworkEyelineLevelFromBench;
}

+ (CGFloat)distanceToTopOfBench
{
    return DistanceToTopOfBenchPortrait;
}

#pragma mark -
#pragma mark Visual Debugging tools

- (void)setupDebugTools
{
    CGRect line = self.view.frame;
    line.size.height = 1;

    UIView *eyeline = [[UIView alloc] initWithFrame:line];
    self.debugEyelineView = eyeline;
    self.debugEyelineView.backgroundColor = [UIColor redColor];
    self.debugEyelineView.clipsToBounds = NO;
    [self.view addSubview: self.debugEyelineView];

    UILabel *eyelineLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, -20, 200, 24)];
    eyelineLabel.text = @"Eyeline";
    eyelineLabel.font = [UIFont serifItalicFontWithSize:12];
    [self.debugEyelineView addSubview:eyelineLabel];

    UIView *lowestPointLine = [[UIView alloc] initWithFrame:line];
    self.debugMinimumArtworkView = lowestPointLine;
    self.debugMinimumArtworkView.backgroundColor = [UIColor greenColor];
    self.debugMinimumArtworkView.clipsToBounds = NO;
    [self.view addSubview: self.debugMinimumArtworkView];

    UILabel *lowestPointLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, -20, 200, 16)];
    lowestPointLabel.text = @"Lowest Point";
    lowestPointLabel.font = [UIFont serifItalicFontWithSize:12];
    [self.debugMinimumArtworkView addSubview:lowestPointLabel];

    UILabel *sizesLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 240)];
    sizesLabel.font = [UIFont serifItalicFontWithSize:12];
    sizesLabel.numberOfLines = 0;
    sizesLabel.center = CGPointMake(160, 240);
    self.debugSizeLabel = sizesLabel;

    [self.view addSubview:sizesLabel];
}

- (void)updateDebugViews
{
    CGRect newframe = self.view.frame;

    newframe.origin.y = CGRectGetHeight(self.view.bounds) - [self.class artworkMinimumDistanceToBottom];
    newframe.size.height = 2;

    self.debugMinimumArtworkView.frame = newframe;

    newframe.origin.y = CGRectGetHeight(self.view.bounds) - [self.class artworkEyelineLevel];
    self.debugEyelineView.frame = newframe;

    self.debugSizeLabel.text = [NSString stringWithFormat:@" %@ \n %@ px \n at %f", self.artwork.dimensionsInches, NSStringFromCGSize(self.artworkImageView.bounds.size), self.zoomScale];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [self.rotationDelegate willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [self.rotationDelegate willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];

    if (self.popOnRotation) {
        if (UIInterfaceOrientationIsPortrait(toInterfaceOrientation)) {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self.rotationDelegate didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

- (NSDictionary *)dictionaryForAnalytics
{
    if (self.artwork) {
        return @{ @"artwork" : self.artwork.artworkID, @"type" : @"artwork" };
    }

    return nil;
}

@end
