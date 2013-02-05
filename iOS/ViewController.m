//
//  ViewController.m
//  InternetMap
//

#import "ViewController.h"
#import "VisualizationsTableViewController.h"
#import "NodeSearchViewController.h"
#import "NodeInformationViewController.h"
#import "ASNRequest.h"
#import <dns_sd.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import "ErrorInfoView.h"
#import "NodeTooltipViewController.h"
#import "MapControllerWrapper.h"
#import "LabelNumberBoxView.h"
#import "NodeWrapper.h"
#import "TimelineInfoViewController.h"
#import "ExpandedSlider.h"

//TODO: move this to a better place.
#define SELECTED_NODE_COLOR UIColorFromRGB(0xffa300)

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

BOOL UIGestureRecognizerStateIsActive(UIGestureRecognizerState state) {
    return state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged || state == UIGestureRecognizerStateRecognized;
}
@interface ViewController ()
@property (strong, nonatomic) ASNRequest* request;
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) MapControllerWrapper* controller;
//@property (strong, nonatomic) MapData* data;

@property (nonatomic) NSMutableArray* tracerouteHops;

@property (strong, nonatomic) NSDate* lastIntersectionDate;
@property (assign, nonatomic) BOOL isHandlingLongPress;

@property (strong, nonatomic) UITapGestureRecognizer* tapRecognizer;
@property (strong, nonatomic) UITapGestureRecognizer* twoFingerTapRecognizer;
@property (strong, nonatomic) UILongPressGestureRecognizer* longPressGestureRecognizer;
@property (strong, nonatomic) UITapGestureRecognizer* doubleTapRecognizer;
@property (strong, nonatomic) UIPanGestureRecognizer* panRecognizer;
@property (strong, nonatomic) UIPinchGestureRecognizer* pinchRecognizer;
@property (strong, nonatomic) UIRotationGestureRecognizer* rotationGestureRecognizer;

@property (nonatomic) CGPoint lastPanPosition;
@property (nonatomic) float lastRotation;

@property (nonatomic) float lastScale;
@property (nonatomic) int isCurrentlyFetchingASN;

@property (strong, nonatomic) SCTracerouteUtility* tracer;


@property (nonatomic) NSTimeInterval updateTime;


@property (nonatomic) NSString* cachedCurrentASN;

@property (nonatomic) int minTimelineYear;

/* UIKit Overlay */
@property (weak, nonatomic) IBOutlet UIView* buttonContainerView;
@property (weak, nonatomic) IBOutlet UIButton* searchButton;
@property (weak, nonatomic) IBOutlet UIButton* youAreHereButton;
@property (weak, nonatomic) IBOutlet UIButton* visualizationsButton;
@property (weak, nonatomic) IBOutlet UIButton* timelineButton;
@property (weak, nonatomic) IBOutlet UIButton* screenshotButton;
@property (weak, nonatomic) IBOutlet UISlider* timelineSlider;
@property (weak, nonatomic) IBOutlet UIButton* playButton;
@property (weak, nonatomic) IBOutlet UIImageView* logo;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView* searchActivityIndicator;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView* youAreHereActivityIndicator;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView* visualizationsActivityIndicator;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView* timelineActivityIndicator;


@property (strong, nonatomic) WEPopoverController* visualizationSelectionPopover;
@property (strong, nonatomic) WEPopoverController* nodeSearchPopover;
@property (strong, nonatomic) WEPopoverController* nodeInformationPopover;
@property (weak, nonatomic) NodeInformationViewController* nodeInformationViewController; //this is weak because it's enough for us that the popover retains the controller. this is only a reference to update the ui of the infoViewController on traceroute callbacks, not to signify ownership
@property (strong, nonatomic) WEPopoverController* timelinePopover;
@property (weak, nonatomic) TimelineInfoViewController* timelineInfoViewController;
@property (strong, nonatomic) WEPopoverController* nodeTooltipPopover;
@property (strong, nonatomic) NodeTooltipViewController* nodeTooltipViewController;

@property (strong, nonatomic) ErrorInfoView* errorInfoView;

@end

@implementation ViewController

- (void)dealloc
{
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View Setup

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    self.preferredFramesPerSecond = 60.0f;

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;

    [EAGLContext setCurrentContext:self.context];
    
    self.controller = [MapControllerWrapper new];
    
    
    //add gesture recognizers
    self.tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    self.twoFingerTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerTap:)];
    self.twoFingerTapRecognizer.numberOfTouchesRequired = 2;
    
    self.doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    self.doubleTapRecognizer.numberOfTapsRequired = 2;
    [self.tapRecognizer requireGestureRecognizerToFail:self.doubleTapRecognizer];
    
    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    self.pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    self.longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    
    self.rotationGestureRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotation:)];
    
    self.tapRecognizer.delegate = self;
    self.doubleTapRecognizer.delegate = self;
    self.twoFingerTapRecognizer.delegate = self;
    self.panRecognizer.delegate = self;
    self.pinchRecognizer.delegate = self;
    self.longPressGestureRecognizer.delegate = self;
    self.rotationGestureRecognizer.delegate = self;
    
    [self.view addGestureRecognizer:self.tapRecognizer];
    [self.view addGestureRecognizer:self.doubleTapRecognizer];
    [self.view addGestureRecognizer:self.twoFingerTapRecognizer];
    [self.view addGestureRecognizer:self.panRecognizer];
    [self.view addGestureRecognizer:self.pinchRecognizer];
    [self.view addGestureRecognizer:self.longPressGestureRecognizer];
    [self.view addGestureRecognizer:self.rotationGestureRecognizer];
    
    //setting activityIndicator sizes (positions are set in IB, but sizes can only be set in code)
    self.searchActivityIndicator.frame = CGRectMake(self.searchActivityIndicator.frame.origin.x, self.searchActivityIndicator.frame.origin.y, 30, 30);
    self.youAreHereActivityIndicator.frame = CGRectMake(self.youAreHereActivityIndicator.frame.origin.x, self.youAreHereActivityIndicator.frame.origin.y, 30, 30);
    self.visualizationsActivityIndicator.frame = CGRectMake(self.visualizationsActivityIndicator.frame.origin.x, self.visualizationsActivityIndicator.frame.origin.y, 30, 30);
    self.timelineActivityIndicator.frame = CGRectMake(self.timelineActivityIndicator.frame.origin.x, self.timelineActivityIndicator.frame.origin.y, 30, 30);
    
    //create error info view
    self.errorInfoView = [[ErrorInfoView alloc] initWithFrame:CGRectMake(10, 70, 300, 40)];
    [self.view addSubview:self.errorInfoView];
    
    
    //customize timeline slider
    float cap = 12;
    UIImage* trackImage = [[UIImage imageNamed:@"timeline-track"] resizableImageWithCapInsets:UIEdgeInsetsMake(0, cap, 0, cap)];
    
    //We're setting the track images to an invisible image here
    //instead, we are drawing an additional UIImageView in the back as the track image
    //this is a workaround to a bug in iOS 5.x
    UIImage* invisibleImage = [HelperMethods imageWithColor:[UIColor clearColor] size:CGSizeMake(1, 1)];
    [self.timelineSlider setMinimumTrackImage:invisibleImage forState:UIControlStateNormal];
    [self.timelineSlider setMaximumTrackImage:invisibleImage forState:UIControlStateNormal];
    
    [self.timelineSlider setThumbImage:[UIImage imageNamed:@"timeline-handle"] forState:UIControlStateNormal];
    [self.timelineSlider addTarget:self action:@selector(timelineSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    
    UIImageView* trackImageView = [[UIImageView alloc] initWithImage:trackImage];
    trackImageView.frame = CGRectMake(-cap, -19, self.timelineSlider.width+2*cap, trackImage.size.height);
    [self.timelineSlider addSubview:trackImageView];
    
    if (!self.timelinePopover) {
        TimelineInfoViewController* tlv = [[TimelineInfoViewController alloc] init];
        self.timelineInfoViewController = tlv;
        self.timelinePopover = [[WEPopoverController alloc] initWithContentViewController:self.timelineInfoViewController];
        if ([HelperMethods deviceIsiPad]) {
            WEPopoverContainerViewProperties* prop = [WEPopoverContainerViewProperties defaultContainerViewProperties];
            prop.downArrowImageName = @"popupArrow-timeline";
            self.timelinePopover.containerViewProperties = prop;
        }else {
            WEPopoverContainerViewProperties* prop = [WEPopoverContainerViewProperties defaultContainerViewProperties];
            prop.downArrowImageName = nil;
            self.timelinePopover.containerViewProperties = prop;
        }

    }
    
    //setup timeline slider values
    NSArray* sortedYears = [self.timelineInfoViewController.jsonDict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSAssert([sortedYears count] >= 2, @"There is not enough data in the history.json file! At least data for two years is required");
    self.minTimelineYear = [sortedYears[0] intValue];
    int max = [[sortedYears lastObject] intValue];
    float diff = max-self.minTimelineYear;
    diff /= 10;
    diff += 0.099; // If we don't add a buffer, current year is only the very last position on the slider
    self.timelineSlider.minimumValue = 0;
    self.timelineSlider.maximumValue = diff;
    self.timelineSlider.value = diff;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(displayInformationPopoverForCurrentNode) name:@"cameraMovementFinished" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissNodeInfoPopover) name:@"lostSelectedNode" object:nil];
    
    [self.controller resetIdleTimer];
    
    self.cachedCurrentASN = nil;
    [self precacheCurrentASN];
    
    self.screenshotButton.hidden = YES;
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    
    return [HelperMethods deviceIsiPad] ? UIInterfaceOrientationIsLandscape(interfaceOrientation) : UIInterfaceOrientationIsPortrait(interfaceOrientation);
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    self.controller.displaySize = CGSizeMake(self.view.bounds.size.width, self.view.bounds.size.height);
    [self.controller setAllowIdleAnimation:[self shouldDoIdleAnimation]];
    [self.controller update:[NSDate timeIntervalSinceReferenceDate]];
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    [self.controller draw];
}

-(void)captureImageToFile:(NSString*)filename {
    float width = self.view.bounds.size.width * [[UIScreen mainScreen] scale];
    float height = self.view.bounds.size.height * [[UIScreen mainScreen] scale];

    GLvoid *imageData = malloc(width*height*4);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, imageData);
    
    CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(NULL, imageData, width*height*4, nil);
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGImageRef imageRef = CGImageCreate(width, height, 8 /* bits per component*/, 32 /* bits per pixel*/, width * 4, colorSpaceRef, kCGBitmapByteOrderDefault, dataProviderRef,    NULL, NO, kCGRenderingIntentDefault);
    
    
    UIImage* image = [UIImage imageWithCGImage:imageRef];
    NSString  *pngPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@",filename]];
    [UIImagePNGRepresentation(image) writeToFile:pngPath atomically:YES];
    
    CGDataProviderRelease(dataProviderRef);
    CGColorSpaceRelease(colorSpaceRef);
    CGImageRelease(imageRef);
    free(imageData);
}

static const int AXIS_DIVISIONS = 8;

-(IBAction)screenshot:(id)sender {
    NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];

    [self.controller draw];
    [self captureImageToFile:@"master.png"];
        
    for(int y = 0; y < AXIS_DIVISIONS; y++) {
        for(int x = 0; x < AXIS_DIVISIONS; x++) {
            CGRect subregion = CGRectMake((float)x / (float)AXIS_DIVISIONS, (float)y / (float)AXIS_DIVISIONS, 1.0f / (float)AXIS_DIVISIONS, 1.0f / (float)AXIS_DIVISIONS);
            [self.controller setViewSubregion:subregion];
            [self.controller update:time];
            [self.controller draw];
            [self captureImageToFile:[NSString stringWithFormat:@"screenshot%.2d.png",(y * AXIS_DIVISIONS) + x]];
        }
    }
    
    CGRect subregion = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
    [self.controller setViewSubregion:subregion];
}

#pragma mark - Touch and GestureRecognizer handlers

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch* touch = [touches anyObject];
    if (touch.view == self.buttonContainerView) {
        return;
    }
    self.isHandlingLongPress = NO;

    [self.controller handleTouchDownAtPoint:[touch locationInView:self.view]];
}

-(void)handleTap:(UITapGestureRecognizer*)gestureRecognizer {
    [self.controller resetIdleTimer];
    [self dismissNodeInfoPopover];
    if (![self.controller selectHoveredNode]) { //couldn't select node
        [self.controller deselectCurrentNode];
    }
}

- (void)handleDoubleTap:(UIGestureRecognizer*)gestureRecongizer {
    [self.controller zoomAnimated:self.controller.currentZoom+1.5 duration:1];
    [self.controller unhoverNode];
}

- (void)handleTwoFingerTap:(UIGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer.numberOfTouches == 2) {
        [self.controller zoomAnimated:self.controller.currentZoom-1.5 duration:1];
        [self.controller unhoverNode];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture
{
    
    if(gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        if ((!self.lastIntersectionDate || fabs([self.lastIntersectionDate timeIntervalSinceNow]) > 0.01)) {
            self.isHandlingLongPress = YES;
            int i = [self.controller indexForNodeAtPoint:[gesture locationInView:self.view]];
            self.lastIntersectionDate = [NSDate date];
            if (i != NSNotFound) {
                
                NodeWrapper* node = [self.controller nodeAtIndex:i];
                if (self.nodeTooltipViewController.node != node) {
                    self.nodeTooltipViewController = [[NodeTooltipViewController alloc] initWithNode:node];
                    
                    [self.nodeTooltipPopover dismissPopoverAnimated:NO];
                    self.nodeTooltipPopover = [[WEPopoverController alloc] initWithContentViewController:self.nodeTooltipViewController];
                    self.nodeTooltipPopover.passthroughViews = @[self.view];
                    CGPoint center = [self.controller getCoordinatesForNodeAtIndex:i];
                    [self.nodeTooltipPopover presentPopoverFromRect:CGRectMake(center.x, center.y, 1, 1) inView:self.view permittedArrowDirections:UIPopoverArrowDirectionDown animated:NO];
                    [self.controller hoverNode:i];
                }
            }
        }
    }else if(gesture.state == UIGestureRecognizerStateEnded) {
        [self.nodeTooltipPopover dismissPopoverAnimated:NO];
        [self dismissNodeInfoPopover];
        [self.controller selectHoveredNode];
    }
     
}

-(void)handlePan:(UIPanGestureRecognizer *)gestureRecognizer
{
    [self.controller resetIdleTimer];
    if (!self.isHandlingLongPress) {
        if ([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
            CGPoint translation = [gestureRecognizer translationInView:self.view];
            self.lastPanPosition = translation;
            [self.controller stopMomentumPan];
            [self.controller unhoverNode];
        }else if([gestureRecognizer state] == UIGestureRecognizerStateChanged) {
            
            CGPoint translation = [gestureRecognizer translationInView:self.view];
            CGPoint delta = CGPointMake(translation.x - self.lastPanPosition.x, translation.y - self.lastPanPosition.y);
            self.lastPanPosition = translation;
            
            [self.controller rotateRadiansX:delta.x * 0.01];
            [self.controller rotateRadiansY:delta.y * 0.01];
        } else if(gestureRecognizer.state == UIGestureRecognizerStateEnded) {
            if (isnan([gestureRecognizer velocityInView:self.view].x) || isnan([gestureRecognizer velocityInView:self.view].y)) {
                [self.controller stopMomentumPan];
            }else {
                CGPoint velocity = [gestureRecognizer velocityInView:self.view];
                [self.controller startMomentumPanWithVelocity:CGPointMake(velocity.x*0.002, velocity.y*0.002)];
            }
        }
    }
}

- (void)handleRotation:(UIRotationGestureRecognizer*)gestureRecognizer {
    [self.controller resetIdleTimer];
    if (!self.isHandlingLongPress) {
        if ([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
            [self.controller unhoverNode];
            self.lastRotation = gestureRecognizer.rotation;
            [self.controller stopMomentumRotation];
        }else if([gestureRecognizer state] == UIGestureRecognizerStateChanged)
        {
            float deltaRotation = -gestureRecognizer.rotation - self.lastRotation;
            self.lastRotation = -gestureRecognizer.rotation;
            [self.controller rotateRadiansZ:deltaRotation];
        } else if(gestureRecognizer.state == UIGestureRecognizerStateEnded) {
            if (isnan(gestureRecognizer.velocity)) {
                [self.controller stopMomentumRotation];
            } else {
                [self.controller startMomentumRotationWithVelocity:-gestureRecognizer.velocity*0.5];
            }

        }
    }
}

-(void)handlePinch:(UIPinchGestureRecognizer *)gestureRecognizer
{
    [self.controller resetIdleTimer];
    if (!self.isHandlingLongPress) {
        if ([gestureRecognizer state] == UIGestureRecognizerStateBegan) {
            [self.controller unhoverNode];
            self.lastScale = gestureRecognizer.scale;
        } else if([gestureRecognizer state] == UIGestureRecognizerStateChanged)
        {
            float deltaZoom = gestureRecognizer.scale - self.lastScale;
            self.lastScale = gestureRecognizer.scale;
            [self.controller zoomByScale:deltaZoom];
        } else if(gestureRecognizer.state == UIGestureRecognizerStateEnded) {
            if (isnan(gestureRecognizer.velocity)) {
                [self.controller stopMomentumZoom];
            } else {
                [self.controller startMomentumZoomWithVelocity:gestureRecognizer.velocity*0.5];
            }
        }
    }
}

#pragma mark - UIGestureRecognizerDelegate methods

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (touch.view == self.view || touch.view == self.errorInfoView || [self.errorInfoView.subviews containsObject:touch.view]) {
        return YES;
    }
    
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    
    
    NSArray* simultaneous = @[self.panRecognizer, self.pinchRecognizer, self.rotationGestureRecognizer, self.longPressGestureRecognizer];
    if ([simultaneous containsObject:gestureRecognizer] && [simultaneous containsObject:otherGestureRecognizer]) {
        return YES;
    }
    
    return NO;
}


- (BOOL)shouldDoIdleAnimation{
    return !UIGestureRecognizerStateIsActive(self.longPressGestureRecognizer.state) && !UIGestureRecognizerStateIsActive(self.pinchRecognizer.state) && !UIGestureRecognizerStateIsActive(self.panRecognizer.state);
}


#pragma mark - Update selected/active node

- (void)updateTargetForIndex:(int)index {
    [self dismissNodeInfoPopover];
    [self nodeSearchDelegateDone];
    [self.controller updateTargetForIndex:index];
}


- (void)selectNodeForASN:(NSString*)asn {
    NodeWrapper* node = [self.controller nodeByASN:asn];
    if (node) {
        [self updateTargetForIndex:node.index];
    } else {
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error locating your node", nil) message:@"Couldn't find a node associated with your IP." delegate:nil cancelButtonTitle:nil otherButtonTitles:@"ok", nil];
        [alert show];
    }
}


#pragma mark - Action methods

-(IBAction)searchButtonPressed:(id)sender {
    //TODO: find out if we can make this work in timeline mode
    if (self.timelineButton.selected) {
        [self leaveTimelineMode];
    }
    [self dismissNodeInfoPopover];
    
    if (!self.nodeSearchPopover) {
        NodeSearchViewController *searchController = [[NodeSearchViewController alloc] init];
        searchController.delegate = self;
        
        self.nodeSearchPopover = [[WEPopoverController alloc] initWithContentViewController:searchController];
        [self.nodeSearchPopover setPopoverContentSize:searchController.contentSizeForViewInPopover];
        self.nodeSearchPopover.delegate = self;
        
        if (![HelperMethods deviceIsiPad]) {
            WEPopoverContainerViewProperties *prop = [WEPopoverContainerViewProperties defaultContainerViewProperties];
            prop.upArrowImageName = nil;
            self.nodeSearchPopover.containerViewProperties = prop;
        }
        searchController.allItems = [self.controller allNodes];
    }
    [self.nodeSearchPopover presentPopoverFromRect:self.searchButton.bounds inView:self.searchButton permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
    self.searchButton.selected = YES;
}

-(IBAction)youAreHereButtonPressed:(id)sender {
    //TODO: find out if we can make this work in timeline mode
    if (self.timelineButton.selected) {
        [self leaveTimelineMode];
    }
    if ([HelperMethods deviceHasInternetConnection]) {
        //fetch current ASN and select node
        if (!self.isCurrentlyFetchingASN) {
            self.isCurrentlyFetchingASN = YES;
            self.youAreHereActivityIndicator.hidden = NO;
            [self.youAreHereActivityIndicator startAnimating];
            self.youAreHereButton.hidden = YES;
            
            void (^error)(void) = ^{
                NSString* error = @"ASN lookup failed";
                NSLog(@"ASN fetching failed with error: %@", error);
                self.isCurrentlyFetchingASN = NO;
                [self.youAreHereActivityIndicator stopAnimating];
                self.youAreHereActivityIndicator.hidden = YES;
                self.youAreHereButton.hidden = NO;
                
                UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error locating your node", nil) message:error delegate:nil cancelButtonTitle:nil otherButtonTitles:@"ok", nil];
                [alert show];
            };
            
            [ASNRequest fetchCurrentASNWithResponseBlock:^(NSArray *asn) {
                NSString* myASN = asn[0];
                if([myASN isEqual:[NSNull null]]) {
                    error();
                }
                else {
                    //NSLog(@"ASN fetched: %@", myASN);
                    self.isCurrentlyFetchingASN = NO;
                    [self.youAreHereActivityIndicator stopAnimating];
                    self.youAreHereActivityIndicator.hidden = YES;
                    self.youAreHereButton.hidden = NO;
                    self.cachedCurrentASN = myASN;
                    [self selectNodeForASN:myASN];
                }
            } errorBlock:error];
        }
    }else {
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:@"No Internet connection" message:@"Please connect to the internet." delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        [alert show];
    }
}

-(IBAction)visualizationsButtonPressed:(id)sender {
    //TODO: find out if we can make this work in timeline mode
    if (self.timelineButton.selected) {
        [self leaveTimelineMode];
    }
    if (!self.visualizationSelectionPopover) {
        VisualizationsTableViewController *tableforPopover = [[VisualizationsTableViewController alloc] initWithStyle:UITableViewStylePlain];
        self.visualizationSelectionPopover = [[WEPopoverController alloc] initWithContentViewController:tableforPopover];
        self.visualizationSelectionPopover.delegate = self;
        tableforPopover.visualizationOptions = [self.controller visualizationNames];
        [self.visualizationSelectionPopover setPopoverContentSize:tableforPopover.contentSizeForViewInPopover];
        if (![HelperMethods deviceIsiPad]) {
            WEPopoverContainerViewProperties *prop = [WEPopoverContainerViewProperties defaultContainerViewProperties];
            prop.upArrowImageName = nil;
            self.visualizationSelectionPopover.containerViewProperties = prop;
        }
        
        __weak ViewController* weakSelf = self;
        
        tableforPopover.selectedBlock = ^(int vis){
            [weakSelf.controller setVisualization:vis];
            [weakSelf.visualizationSelectionPopover dismissPopoverAnimated:YES];
            weakSelf.visualizationsButton.selected = NO;
        };
    }
    [self.visualizationSelectionPopover presentPopoverFromRect:self.visualizationsButton.bounds inView:self.visualizationsButton permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
    self.visualizationsButton.selected = YES;
}

-(IBAction)timelineButtonPressed:(id)sender {
    if (self.timelineSlider.hidden) {
        self.timelineSlider.hidden = NO;
        self.timelineButton.selected = YES;
        self.playButton.hidden = NO;
        
        int year = (int)(self.minTimelineYear+self.timelineSlider.value*10);
        [self.controller setTimelinePoint:[NSString stringWithFormat:@"%d0101", year]];

        // Poke node info popover so it'll switch styles, note: camera move when reselecting node will
        // show it again
        [self dismissNodeInfoPopover];
    } else {
        [self leaveTimelineMode];
    }
}

-(void)leaveTimelineMode {
    self.timelineSlider.hidden = YES;
    self.timelineButton.selected = NO;
    self.playButton.hidden = YES;
    [self.controller setTimelinePoint:@""];
    self.timelineSlider.value = self.timelineSlider.maximumValue;
    
    // Poke node info popover so it'll switch styles, note: camera move when reselecting node will
    // show it again
    [self dismissNodeInfoPopover];
}

-(void)displayInformationPopoverForCurrentNode {
    NodeWrapper* node;
    
    if(self.controller.targetNode != INT_MAX) {
        node = [self.controller nodeAtIndex:self.controller.targetNode];
        if(!node) {
            return;
        }
    }
    else {
        return;
    }
    
    if (self.timelineSlider.hidden == NO) {
        // in timeline mdoe, we just show tooltip-style popover
        [self.nodeInformationPopover dismissPopoverAnimated:NO];
        self.nodeInformationPopover = [[WEPopoverController alloc] initWithContentViewController:[[NodeTooltipViewController alloc] initWithNode:node]];
        self.nodeInformationPopover.passthroughViews = @[self.view];
        CGPoint center = [self.controller getCoordinatesForNodeAtIndex:self.controller.targetNode];
        [self.nodeInformationPopover presentPopoverFromRect:CGRectMake(center.x, center.y, 1, 1) inView:self.view permittedArrowDirections:UIPopoverArrowDirectionDown animated:NO];
    }
    else {
        //check if node is the current node
        BOOL isSelectingCurrentNode = NO;
        if (!self.cachedCurrentASN) {
            NodeWrapper* node = [self.controller nodeByASN:[NSString stringWithFormat:@"%@", self.cachedCurrentASN]];
            if (node.index == self.controller.targetNode) {
                isSelectingCurrentNode = YES;
            }
        }

        NodeWrapper* node = [self.controller nodeAtIndex:self.controller.targetNode];
        
        //careful, the local assignment first is necessary, because the property is a weak reference
        NodeInformationViewController* controller = [[NodeInformationViewController alloc] initWithNode:node isCurrentNode:isSelectingCurrentNode];
        self.nodeInformationViewController = controller;
        self.nodeInformationViewController.delegate = self;
        //NSLog(@"ASN:%@, Text Desc: %@", node.asn, node.textDescription);
        
        [self dismissNodeInfoPopover];
        //this line is important, in case the popover for another node is already visible and traceroute could be being performed
        self.nodeInformationPopover = [[WEPopoverController alloc] initWithContentViewController:self.nodeInformationViewController];
        self.nodeInformationPopover.delegate = self;
        self.nodeInformationPopover.passthroughViews = @[self.view];
        UIPopoverArrowDirection dir = UIPopoverArrowDirectionLeft;

        if (![HelperMethods deviceIsiPad]) {
            WEPopoverContainerViewProperties* prop = [WEPopoverContainerViewProperties defaultContainerViewProperties];
            prop.upArrowImageName = nil;
            self.nodeInformationPopover.containerViewProperties = prop;
            dir = UIPopoverArrowDirectionUp;
        }
            
        [self.nodeInformationPopover presentPopoverFromRect:[self displayRectForNodeInfoPopover] inView:self.view permittedArrowDirections:dir animated:YES];
        
        if(isSelectingCurrentNode) {
            self.youAreHereButton.selected = YES;
        }
    }
}



- (IBAction)playButtonPressed:(id)sender{

}



- (IBAction)timelineSliderValueChanged:(id)sender {
    int year = (int)(self.minTimelineYear+self.timelineSlider.value*10);
    CGRect thumbRect = [self.timelineSlider thumbRectForBounds:self.timelineSlider.bounds trackRect:[self.timelineSlider trackRectForBounds:self.timelineSlider.bounds] value:self.timelineSlider.value];
    thumbRect = [self.view convertRect:thumbRect fromView:self.timelineSlider];
    if (![HelperMethods deviceIsiPad]) {
        thumbRect.origin.y -= 5;
    }
    
    [self.timelinePopover dismissPopoverAnimated:NO];
    
    [self.timelineInfoViewController setYear:year];
    [self.timelinePopover setPopoverContentSize:self.timelineInfoViewController.contentSizeForViewInPopover];
    [self.timelinePopover presentPopoverFromRect:thumbRect inView:self.view permittedArrowDirections:UIPopoverArrowDirectionDown animated:NO];
    
}

- (void)timelineSliderTouchUp:(id)sender {
    int year = (int)(self.minTimelineYear+self.timelineSlider.value*10);
    [self.controller setTimelinePoint:[NSString stringWithFormat:@"%d0101", year]];
    [self.timelinePopover dismissPopoverAnimated:NO];
    [self dismissNodeInfoPopover];
}

#pragma mark - Helper Methods: Current ASN precaching

- (void)precacheCurrentASN {
    
    void (^error)(void) = ^{
        //do nothing when precaching fails
    };
    
    
    [ASNRequest fetchCurrentASNWithResponseBlock:^(NSArray *asn) {
        NSString* myASN = asn[0];
        if([myASN isEqual:[NSNull null]]) {
            error();
        }
        else {
            self.cachedCurrentASN = myASN;
        }
    } errorBlock:error];
}


#pragma mark - NodeSearch Delegate

-(void)nodeSelected:(NodeWrapper*)node{
    [self updateTargetForIndex:node.index];
    [self nodeSearchDelegateDone];
}

-(void)selectNodeByHostLookup:(NSString*)host {
    [self.nodeSearchPopover dismissPopoverAnimated:YES];
    self.searchButton.selected = NO;

    if ([HelperMethods deviceHasInternetConnection]) {
        // TODO :detect an IP address and call fetchASNForIP directly rather than doing no-op lookup
        [self.searchActivityIndicator startAnimating];
        self.searchButton.hidden = YES;
        [[SCDispatchQueue defaultPriorityQueue] dispatchAsync:^{
            NSArray* addresses = [ASNRequest addressesForHostname:host];
            if(addresses.count != 0) {
                self.controller.lastSearchIP = addresses[0];
                [ASNRequest fetchForAddresses:@[addresses[0]] responseBlock:^(NSArray *asn) {
                    [self.searchActivityIndicator stopAnimating];
                    self.searchButton.hidden = NO;
                    NSString* myASN = asn[0];
                    if([myASN isEqual:[NSNull null]]) {
                        [self.errorInfoView setErrorString:@"Couldn't resolve address for hostname."];
                    }
                    else {
                        [self selectNodeForASN:myASN];
                    }
                }];
            }
        }];
    } else {
        UIAlertView* alert = [[UIAlertView alloc] initWithTitle:@"No Internet connection" message:@"Please connect to the internet." delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        [alert show];
    }
}

-(void)nodeSearchDelegateDone {
    [self.nodeSearchPopover dismissPopoverAnimated:YES];
    self.searchButton.selected = NO;
}

#pragma mark - NodeInfo delegate

- (void)dismissNodeInfoPopover {
    [self.tracer stop];
    self.tracer = nil;
    self.youAreHereButton.selected = NO;
    [self.nodeInformationPopover dismissPopoverAnimated:YES];
    [self.nodeInformationViewController.tracerouteTimer invalidate];
    if (self.tracerouteHops) {
        self.tracerouteHops = nil;
        [self.controller clearHighlightLines];
    }
}

#pragma mark - Node Info View Delegate

- (CGRect)displayRectForNodeInfoPopover{
    CGRect displayRect;
    CGPoint center = [self.controller getCoordinatesForNodeAtIndex:self.controller.targetNode];
    
    if (![HelperMethods deviceIsiPad]) {
        displayRect = CGRectMake(center.x, self.controller.displaySize.height-self.nodeInformationViewController.contentSizeForViewInPopover.height, 1, 1);
    }else {
        displayRect = CGRectMake(center.x, center.y, 1, 1);
    }
    
    return displayRect;
}

- (void)resizeNodeInfoPopover {
    self.nodeInformationPopover.popoverContentSize = CGSizeZero;
    UIPopoverArrowDirection dir = [HelperMethods deviceIsiPad] ? UIPopoverArrowDirectionLeft : UIPopoverArrowDirectionUp;
    [self.nodeInformationPopover repositionPopoverFromRect:[self displayRectForNodeInfoPopover] inView:self.view permittedArrowDirections:dir animated:YES];
}

-(void)tracerouteButtonTapped{
    
    [self resizeNodeInfoPopover];
    
    self.tracerouteHops = [NSMutableArray array];
    [self.controller zoomAnimated:-3 duration:3];
    
    NodeWrapper* node = [self.controller nodeAtIndex:self.controller.targetNode];
    // Ask Alex what this does - best guess is adjusts the camera distance/focal length?
    if (node.importance > 0.006) {
        [self.controller rotateAnimated:GLKMatrix4Identity duration:3];
    } else {
        [self.controller rotateAnimated:GLKMatrix4MakeRotation(M_PI, 0, 1, 0) duration:3];
    }
    
    if(self.controller.lastSearchIP && ![self.controller.lastSearchIP isEqualToString:@""]) {
        self.tracer = [SCTracerouteUtility tracerouteWithAddress:self.controller.lastSearchIP];
        self.tracer.delegate = self;
        [self.tracer start];
    } else {
        NodeWrapper* node = [self.controller nodeAtIndex:self.controller.targetNode];
        if (node.asn) {
            [ASNRequest fetchIPsForASN:node.asn responseBlock:^(NSArray *ipsFromWire) {
                //We arbitrarily select any of the prefix IPs and try for a traceroute using it
                //We do this because we have no reliable way of knowing what machines will reslond to our ICMP packets
                //So, if we can contact even one machine within an ASN - any one at all - we know we travel through that ASN
                //We select randomly because why the heck not? It's all a guess as to which will respond. :)
                
                NSArray* ips = ipsFromWire[0];
                uint32_t rnd = arc4random_uniform([ips count]);
                if ([ips count]) {
                    NSString* arbitraryIP = [NSString stringWithFormat:@"%@", ips[rnd]];
                    NSLog(@"Starting traceroute with IP: %@", arbitraryIP );
                    self.tracer = [SCTracerouteUtility tracerouteWithAddress:arbitraryIP];
                    self.tracer.delegate = self;
                    [self.tracer start];
                } else {
                    [self couldntResolveIP];
                }
            }];
            
        } else {
            [self couldntResolveIP];
        }
    }
     
}

-(void)couldntResolveIP{
    self.nodeInformationViewController.tracerouteTextView.textColor = [UIColor redColor];
    self.nodeInformationViewController.tracerouteTextView.text = @"Error: ASN couldn't be resolved into IP. Please try another node!";
}

-(void)doneTapped{
    [self dismissNodeInfoPopover];
    [self.controller deselectCurrentNode];
}

#pragma mark - WEPopover Delegate

//Pretty sure these don't get called for NodeInfoPopover, but will get called for other popovers if we set delegates, yo
- (void)popoverControllerDidDismissPopover:(WEPopoverController *)popoverController{

}

- (BOOL)popoverControllerShouldDismissPopover:(WEPopoverController *)popoverController{
    self.visualizationsButton.selected = NO;
    self.searchButton.selected = NO;
    return YES;
}

#pragma mark - SCTracerouteUtility Delegate

- (void)tracerouteDidFindHop:(NSString*)report withHops:(NSArray *)hops{
    
    NSLog(@"%@", report);
    
    self.nodeInformationViewController.tracerouteTextView.text = [[NSString stringWithFormat:@"%@\n%@", self.nodeInformationViewController.tracerouteTextView.text, report] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self.nodeInformationViewController.box1 incrementNumber];
    
    if ([hops count] <= 0) {
        return;
    }
    
    [ASNRequest fetchForAddresses:@[[hops lastObject]] responseBlock:^(NSArray *asns) {
        NodeWrapper* last = [self.tracerouteHops lastObject];
        
        for(NSString* asn in asns) {
            NodeWrapper* current =  [self.controller nodeByASN:[NSString stringWithFormat:@"%@", asn]];
            if(current && current != last) {
                [self.tracerouteHops addObject:current];
            }
        }
        
        if ([self.tracerouteHops count] >= 2) {
            [self.controller highlightRoute:self.tracerouteHops];
        }
        
        //update node info label for number of unique ASN Hops
        NSMutableSet* asnSet = [NSMutableSet set];
        for (int i = 0; i < [self.tracerouteHops count]; i++) {
            NodeWrapper* node = self.tracerouteHops[i];
            [asnSet addObject:node.asn];
        }
        self.nodeInformationViewController.box2.numberLabel.text = [NSString stringWithFormat:@"%i", [asnSet count]];
        
    }];

}

- (void)tracerouteDidComplete:(NSMutableArray*)hops{
    [self.tracer stop];
    self.tracer = nil;
    self.nodeInformationViewController.tracerouteTextView.text = [[NSString stringWithFormat:@"%@\nTraceroute complete.", self.nodeInformationViewController.tracerouteTextView.text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self.nodeInformationViewController.tracerouteTimer invalidate];
    [self.nodeInformationViewController tracerouteDone];
    [self resizeNodeInfoPopover];

    //highlight last node if not already highlighted
    NodeWrapper* node = [self.tracerouteHops lastObject];
    if (node.index != self.controller.targetNode) {
        [self.tracerouteHops addObject:[self.controller nodeAtIndex:self.controller.targetNode]];
        [self.controller highlightRoute:self.tracerouteHops];
    }

}

-(void)tracerouteDidTimeout{
    [self.tracer stop];
    self.tracer = nil;
    self.nodeInformationViewController.tracerouteTextView.text = [[NSString stringWithFormat:@"%@\nTraceroute completed with as many hops as we could contact.", self.nodeInformationViewController.tracerouteTextView.text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self.nodeInformationViewController.tracerouteTimer invalidate];
    [self.nodeInformationViewController tracerouteDone];
    [self resizeNodeInfoPopover];

    //highlight last node if not already highlighted
    NodeWrapper* node = [self.tracerouteHops lastObject];
    if (node.index != self.controller.targetNode) {
        [self.tracerouteHops addObject:[self.controller nodeAtIndex:self.controller.targetNode]];
        [self.controller highlightRoute:self.tracerouteHops];
    }
}

@end