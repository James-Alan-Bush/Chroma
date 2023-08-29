//
//  ViewController.m
//  Chroma
//
//  Created by Xcode Developer on 8/29/23.
//


@import AVFoundation;
@import Photos;

#import "ViewController.h"
#import "PreviewView.h"
#import "AppDelegate.h"

#import <objc/runtime.h>
#import <objc/NSObjCRuntime.h>

static void * SessionRunningContext = &SessionRunningContext;
static void * FocusModeContext = &FocusModeContext;
static void * ExposureModeContext = &ExposureModeContext;
static void * TorchLevelContext = &TorchLevelContext;
static void * LensPositionContext = &LensPositionContext;
static void * ExposureDurationContext = &ExposureDurationContext;
static void * ISOContext = &ISOContext;
static void * ExposureTargetBiasContext = &ExposureTargetBiasContext;
static void * ExposureTargetOffsetContext = &ExposureTargetOffsetContext;
static void * VideoZoomFactorContext = &VideoZoomFactorContext;
static void * PresetsContext = &PresetsContext;

static void * DeviceWhiteBalanceGainsContext = &DeviceWhiteBalanceGainsContext;
static void * WhiteBalanceModeContext = &WhiteBalanceModeContext;

typedef NS_ENUM( NSInteger, AVCamManualSetupResult ) {
    AVCamManualSetupResultSuccess,
    AVCamManualSetupResultCameraNotAuthorized,
    AVCamManualSetupResultSessionConfigurationFailed
};

@interface ViewController () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, weak) IBOutlet PreviewView *previewView;
@property (nonatomic, weak) IBOutlet UIImageView * cameraUnavailableImageView;
@property (nonatomic, weak) IBOutlet UIButton *resumeButton;
@property (nonatomic, weak) IBOutlet UIButton *recordButton;
@property (nonatomic, weak) IBOutlet UIButton *HUDButton;
@property (nonatomic, weak) IBOutlet UIView *manualHUD;
@property (nonatomic, weak) IBOutlet UIView *controlsView;

@property (nonatomic) NSArray *focusModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDFocusView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *focusModeControl;
@property (nonatomic, weak) IBOutlet UISlider *lensPositionSlider;

@property (nonatomic) NSArray *exposureModes;
@property (nonatomic, weak) IBOutlet UIView *manualHUDExposureView;
@property (nonatomic, weak) IBOutlet UISegmentedControl *exposureModeControl;
@property (nonatomic, weak) IBOutlet UISlider *exposureDurationSlider;
@property (nonatomic, weak) IBOutlet UISlider *ISOSlider;

@property (weak, nonatomic) IBOutlet UIView *manualHUDVideoZoomFactorView;
@property (weak, nonatomic) IBOutlet UISlider *videoZoomFactorSlider;

@property (weak, nonatomic) IBOutlet UIView *manualHUDTorchLevelView;
@property (weak, nonatomic) IBOutlet UISlider *torchLevelSlider;

@property (strong, nonatomic) UILongPressGestureRecognizer *rescaleLensPositionSliderValueRangeGestureRecognizer;

@property (nonatomic) NSArray *whiteBalanceModes;
@property (weak, nonatomic) IBOutlet UIView *manualHUDWhiteBalanceView;
@property (weak, nonatomic) IBOutlet UISegmentedControl *whiteBalanceModeControl;
@property (weak, nonatomic) IBOutlet UISlider *temperatureSlider;
@property (weak, nonatomic) IBOutlet UISlider *tintSlider;
@property (weak, nonatomic) IBOutlet UIButton *grayWorldButton;
@property (weak, nonatomic) IBOutlet UIView *coverView;

// Session management
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureDeviceDiscoverySession *videoDeviceDiscoverySession;
@property (nonatomic) AVCaptureDevice *videoDevice;

// Utilities
@property (nonatomic) AVCamManualSetupResult setupResult;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;

@end

@implementation ViewController


static const float kExposureMinimumDuration = 1.0/1000; // Limit exposure duration to a useful range
static const double kVideoZoomFactorPowerCoefficient = 3.333f; // Higher numbers will give the slider more sensitivity at shorter durations
static const float kExposureDurationPower = 5.f; // Higher numbers will give the slider more sensitivity at shorter durations

#pragma mark View Controller Life Cycle

- (void)toggleControlViewVisibility:(NSArray *)views hide:(BOOL)shouldHide
{
    [views enumerateObjectsUsingBlock:^(UIView *  _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        [view setHidden:shouldHide];
        [view setAlpha:(shouldHide) ? 0.0 : 1.0];
    }];
}


- (IBAction)toggleCoverView:(UIButton *)sender {
    [self.coverView setHidden:TRUE];
    [self.coverView setAlpha:0.0];
}



- (IBAction)toggleDisplay:(UIButton *)sender {
    [self.coverView setHidden:FALSE];
    [self.coverView setAlpha:1.0];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.recordButton setImage:[UIImage systemImageNamed:@"stop.circle"] forState:UIControlStateSelected];
    [self.recordButton setImage:[UIImage systemImageNamed:@"record.circle"] forState:UIControlStateNormal];
    
    self.session = [[AVCaptureSession alloc] init];
    
    NSArray<NSString *> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera];
    self.videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
    
    self.previewView.capture_session = self.session;
    
    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    
    self.setupResult = AVCamManualSetupResultSuccess;
    
    switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] )
    {
        case AVAuthorizationStatusAuthorized:
        {
            AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
            
            if ( [self.session canAddOutput:movieFileOutput] ) {
                [self.session beginConfiguration];
                [self.session addOutput:movieFileOutput];
                self.session.sessionPreset = AVCaptureSessionPreset3840x2160;
                AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
                if ( connection.isVideoStabilizationSupported ) {
                    connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
                }
                [self.session commitConfiguration];
                
                self.movieFileOutput = movieFileOutput;
                
                dispatch_async( dispatch_get_main_queue(), ^{
                    self.recordButton.enabled = YES;
                    self.HUDButton.enabled = YES;
                } );
                
                
            }
            
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            dispatch_suspend( self.sessionQueue );
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    self.setupResult = AVCamManualSetupResultCameraNotAuthorized;
                }
                dispatch_resume( self.sessionQueue );
            }];
            break;
        }
        default:
        {
            self.setupResult = AVCamManualSetupResultCameraNotAuthorized;
            break;
        }
    }
    
    dispatch_async( self.sessionQueue, ^{
        [self configureSession];
    } );
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    dispatch_async( self.sessionQueue, ^{
        switch ( self.setupResult )
        {
            case AVCamManualSetupResultSuccess:
            {
                [self addObservers];
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                
                break;
            }
            case AVCamManualSetupResultCameraNotAuthorized:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"AVCamManual doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    
                    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"Settings", @"Alert button to open Settings" ) style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                    }];
                    [alertController addAction:settingsAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
            case AVCamManualSetupResultSessionConfigurationFailed:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"Unable to capture media", @"Alert message when something goes wrong during capture session configuration" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
        }
    } );
}

- (void)viewDidDisappear:(BOOL)animated
{
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult == AVCamManualSetupResultSuccess ) {
            [self.session stopRunning];
            [self removeObservers];
        }
    } );
    
    [super viewDidDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    
    
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark HUD

- (IBAction)longPress:(UILongPressGestureRecognizer *)sender {
    printf("longPress == %f\n", ((UISlider *)(sender.delegate)).value);
}

- (void)configureManualHUD
{
    self.focusModes = @[@(AVCaptureFocusModeContinuousAutoFocus), @(AVCaptureFocusModeLocked)];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        __autoreleasing NSError *error;
        if ([self->_videoDevice lockForConfiguration:&error]) {
            [self.focusModeControl setSelectedSegmentIndex:0];
            [self changeFocusMode:self.focusModeControl];
            self.lensPositionSlider.minimumValue = 0.0;
            self.lensPositionSlider.maximumValue = 1.0;
            self.lensPositionSlider.value = self.videoDevice.lensPosition;
            [self.lensPositionSlider setMinimumTrackTintColor:[UIColor systemYellowColor]];
            [self.lensPositionSlider setMaximumTrackTintColor:[UIColor systemBlueColor]];
            [self.lensPositionSlider setThumbTintColor:[UIColor whiteColor]];
            rescale_lens_position = set_lens_position_scale(0.f, 1.f, 0.f, 1.f);
            
            self.rescaleLensPositionSliderValueRangeGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self.rescaleLensPositionSliderValueRangeGestureRecognizer action:@selector(rescaleLensPositionSliderRange:)];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setAllowableMovement:20];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setMinimumPressDuration:(NSTimeInterval)0.5];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setNumberOfTapsRequired:1];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setNumberOfTouchesRequired:1];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setDelaysTouchesBegan:FALSE];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setDelaysTouchesEnded:FALSE];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setCancelsTouchesInView:TRUE];
            [self.rescaleLensPositionSliderValueRangeGestureRecognizer setRequiresExclusiveTouchType:FALSE];
            [self.lensPositionSlider addGestureRecognizer:self.rescaleLensPositionSliderValueRangeGestureRecognizer];
            
            self.exposureModes = @[@(AVCaptureExposureModeContinuousAutoExposure), @(AVCaptureExposureModeCustom)];
            self.exposureModeControl.enabled = ( self.videoDevice != nil );
            [self.exposureModeControl setSelectedSegmentIndex:0];
            for ( NSNumber *mode in self.exposureModes ) {
                [self.exposureModeControl setEnabled:[self.videoDevice isExposureModeSupported:mode.intValue] forSegmentAtIndex:[self.exposureModes indexOfObject:mode]];
            }
            [self changeExposureMode:self.exposureModeControl];
            
            self.exposureDurationSlider.minimumValue = 0.f;
            self.exposureDurationSlider.maximumValue = 1.f;
            double exposureDurationSeconds = CMTimeGetSeconds( self.videoDevice.exposureDuration );
            double minExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 1000.f), 1000*1000*1000));
            double maxExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 3.f), 1000*1000*1000));
            self.exposureDurationSlider.value = property_control_value(exposureDurationSeconds, minExposureDurationSeconds, maxExposureDurationSeconds, kExposureDurationPower, 0.f);
            
            self.exposureDurationSlider.enabled = ( self.videoDevice && self.videoDevice.exposureMode == AVCaptureExposureModeCustom);
            
        
            self.ISOSlider.minimumValue = 0.f; //;
            self.ISOSlider.maximumValue = 1.f; //self.videoDevice.activeFormat.maxISO;
            self.ISOSlider.value = property_control_value(self.videoDevice.ISO, self.videoDevice.activeFormat.minISO, self.videoDevice.activeFormat.maxISO, 1.f, 0.f);
            self.ISOSlider.enabled = ( self.videoDevice.exposureMode == AVCaptureExposureModeCustom );
            
            self.videoZoomFactorSlider.minimumValue = 0.0;
            self.videoZoomFactorSlider.maximumValue = 1.0;
            self.videoZoomFactorSlider.value = property_control_value(self.videoDevice.videoZoomFactor, self.videoDevice.minAvailableVideoZoomFactor, self.videoDevice.activeFormat.videoMaxZoomFactor, kVideoZoomFactorPowerCoefficient, 0.f);
            self.videoZoomFactorSlider.enabled = YES;
            
            
            
            // To-Do: Restore these for "color-contrasting" overwhite/overblack subject areas (where luminosity contrasting fails)
            
            // Manual white balance controls
            self.whiteBalanceModes = @[@(AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance), @(AVCaptureWhiteBalanceModeLocked)];
            
            self.whiteBalanceModeControl.enabled = (self.videoDevice != nil);
            self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(self.videoDevice.whiteBalanceMode)];
            for ( NSNumber *mode in self.whiteBalanceModes ) {
                [self.whiteBalanceModeControl setEnabled:[self.videoDevice isWhiteBalanceModeSupported:mode.intValue] forSegmentAtIndex:[self.whiteBalanceModes indexOfObject:mode]];
            }
            
            AVCaptureWhiteBalanceGains whiteBalanceGains = self.videoDevice.deviceWhiteBalanceGains;
            AVCaptureWhiteBalanceTemperatureAndTintValues whiteBalanceTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:whiteBalanceGains];
            
            //            temp (yellow/blue) and tint (magenta/green)
            
            [self.temperatureSlider setMaximumValueImage:[UIImage systemImageNamed:@"b.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor systemBlueColor]]]];
            [self.temperatureSlider setMinimumValueImage:[UIImage systemImageNamed:@"y.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor systemYellowColor]]]];
            self.temperatureSlider.minimumValue = 0.f;
            self.temperatureSlider.maximumValue = 1.f;
            self.temperatureSlider.value = property_control_value(whiteBalanceTemperatureAndTint.temperature, 3000.f, 8000.f, 1.f, 0.f);
            self.temperatureSlider.enabled = ( self.videoDevice && self.videoDevice.whiteBalanceMode == AVCaptureWhiteBalanceModeLocked );
            
            [self.tintSlider setMinimumValueImage:[UIImage systemImageNamed:@"m.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor colorWithRed:0.8470588235f green:0.06274509804f blue:0.4941176471f alpha:1.f]]]];
            [self.tintSlider setMaximumValueImage:[UIImage systemImageNamed:@"g.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor systemGreenColor]]]];
            
            self.tintSlider.minimumValue = 0.f;
            self.tintSlider.maximumValue = 1.f;
            self.tintSlider.value = property_control_value(whiteBalanceTemperatureAndTint.tint, -150.f, 150.f, 1.f, 0.f);
            self.tintSlider.enabled = ( self.videoDevice && self.videoDevice.whiteBalanceMode == AVCaptureWhiteBalanceModeLocked );
            
            if ([self->_videoDevice isTorchActive])
                [self->_videoDevice setTorchMode:0];
            //            else
            //                [self->_videoDevice setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
        } else {
            NSLog(@"AVCaptureDevice lockForConfiguration returned error\t%@", error);
        }
        [self->_videoDevice unlockForConfiguration];
    });
}

//- (IBAction)toggleTorch:(id)sender
//{
//    NSLog(@"%s", __PRETTY_FUNCTION__);
//    dispatch_async(dispatch_get_main_queue(), ^{
//        __autoreleasing NSError *error;
//        if ([self->_videoDevice lockForConfiguration:&error]) {
//            if ([self->_videoDevice isTorchActive])
//                [self->_videoDevice setTorchMode:0];
//            else
//                [self->_videoDevice setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
//        } else {
//            NSLog(@"AVCaptureDevice lockForConfiguration returned error\t%@", error);
//        }
//        [self->_videoDevice unlockForConfiguration];
//    });
//}

- (IBAction)toggleHUD:(UIButton *)sender
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [sender setSelected:self.manualHUD.hidden = !self.manualHUD.hidden];
        [sender setHighlighted:!self.manualHUD.hidden];
    });
}

- (IBAction)changeManualHUDSelection:(UISegmentedControl *)sender {
    for (UIView * view in self.controlsView.subviews) {
        BOOL shouldHide = (view.tag == sender.selectedSegmentIndex) ? !view.hidden : TRUE;
        view.hidden = shouldHide;
        [view setAlpha:!shouldHide];
    };
    
    //    switch (sender.selectedSegmentIndex) {
    //        case 0:
    //            self.manualHUDTorchLevelView.hidden = !self.manualHUDTorchLevelView.hidden;
    //            break;
    //        case 1:
    //            self.manualHUDTorchLevelView.hidden = !self.manualHUDTorchLevelView.hidden;
    //            break;
    //        case 2:
    //            self.manualHUDFocusView.hidden = !self.manualHUDFocusView.hidden;
    //            break;
    //        case 3:
    //            self.manualHUDExposureView.hidden = !self.manualHUDExposureView.hidden;
    //            break;
    //        case 4:
    //            self.manualHUDVideoZoomFactorView.hidden = !self.manualHUDVideoZoomFactorView.hidden;
    //            break;
    //        case 5:
    //            self.manualHUDWhiteBalanceView.hidden = !self.manualHUDWhiteBalanceView.hidden;
    //            break;
    //
    //        default:
    //            self.manualHUD.hidden = !self.manualHUD.hidden;
    //    }
}

#pragma mark Session Management

// Should be called on the session queue
- (void)configureSession
{
    if ( self.setupResult != AVCamManualSetupResultSuccess ) {
        return;
    }
    
    NSError *error = nil;
    
    [self.session beginConfiguration];
    
    self.session.sessionPreset = AVCaptureSessionPreset3840x2160;
    [self.session setAutomaticallyConfiguresCaptureDeviceForWideColor:TRUE];
    
    // Add video input
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if ( ! videoDeviceInput ) {
        NSLog( @"Could not create video device input: %@", error );
        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    if ( [self.session canAddInput:videoDeviceInput] ) {
        [self.session addInput:videoDeviceInput];
        self.videoDeviceInput = videoDeviceInput;
        self.videoDevice = videoDevice;
        
        // Configure default camera focus and exposure properties (set to manual vs. auto)
        __autoreleasing NSError *error = nil;
        [self.videoDevice lockForConfiguration:&error];
        @try {
            [self.videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            [self.videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        } @catch (NSException *exception) {
            NSLog(@"Error setting focus mode: %@", error.description);
        } @finally {
            [self.videoDevice unlockForConfiguration];
        }
        
        //  Enable low-light boost
        __autoreleasing NSError *automaticallyEnablesLowLightBoostWhenAvailableError = nil;
        [self.videoDevice lockForConfiguration:&automaticallyEnablesLowLightBoostWhenAvailableError];
        @try {
            [self.videoDevice setAutomaticallyEnablesLowLightBoostWhenAvailable:TRUE];
        } @catch (NSException *exception) {
            NSLog(@"Error enabling automatic low light boost: %@", automaticallyEnablesLowLightBoostWhenAvailableError.description);
        } @finally {
            [self.videoDevice unlockForConfiguration];
        }
        
//        dispatch_async( dispatch_get_main_queue(), ^{
//            UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
//            if ( UIDeviceOrientationIsPortrait( deviceOrientation ) || UIDeviceOrientationIsLandscape( deviceOrientation ) ) {
//                AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
//                AVCaptureDeviceRotationCoordinator * rotation_coord = [[AVCaptureDeviceRotationCoordinator alloc] initWithDevice:self->_videoDevice previewLayer:preview_layer(self->_previewView)];
//                previewLayer.connection.videoRotationAngle = rotation_coord.videoRotationAngleForHorizonLevelCapture;
//            }
//        } );
    }
    else {
        NSLog( @"Could not add video device input to the session" );
        self.setupResult = AVCamManualSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    
    // Add audio input
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    if ( ! audioDeviceInput ) {
        NSLog( @"Could not create audio device input: %@", error );
    }
    if ( [self.session canAddInput:audioDeviceInput] ) {
        [self.session addInput:audioDeviceInput];
    }
    else {
        NSLog( @"Could not add audio device input to the session" );
    }
    
    
    // We will not create an AVCaptureMovieFileOutput when configuring the session because the AVCaptureMovieFileOutput does not support movie recording with AVCaptureSessionPresetPhoto
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    
    [self.session commitConfiguration];
    
    dispatch_async( dispatch_get_main_queue(), ^{
        [self configureManualHUD];
    } );
}

- (IBAction)resumeInterruptedSession:(id)sender
{
    dispatch_async( self.sessionQueue, ^{
        [self.session startRunning];
        self.sessionRunning = self.session.isRunning;
        if ( ! self.session.isRunning ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *message = NSLocalizedString( @"Unable to resume", @"Alert message when unable to resume the session running" );
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCamManual" message:message preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:cancelAction];
                [self presentViewController:alertController animated:YES completion:nil];
            } );
        }
        else {
            dispatch_async( dispatch_get_main_queue(), ^{
                self.resumeButton.hidden = YES;
            } );
        }
    } );
}

#pragma mark Device Configuration

- (void)changeCameraWithDevice:(AVCaptureDevice *)newVideoDevice
{
    // Check if device changed
    if ( newVideoDevice == self.videoDevice ) {
        return;
    }
    
    self.manualHUD.userInteractionEnabled = NO;
    //    self.cameraButton.enabled = NO;
    self.recordButton.enabled = NO;
    //    self.photoButton.enabled = NO;
    //    self.captureModeControl.enabled = NO;
    //    self.HUDButton.enabled = NO;
    
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:newVideoDevice error:nil];
        
        [self.session beginConfiguration];
        
        // Remove the existing device input first, since using the front and back camera simultaneously is not supported
        [self.session removeInput:self.videoDeviceInput];
        if ( [self.session canAddInput:newVideoDeviceInput] ) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDevice];
            
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:newVideoDevice];
            
            [self.session addInput:newVideoDeviceInput];
            self.videoDeviceInput = newVideoDeviceInput;
            self.videoDevice = newVideoDevice;
        }
        else {
            [self.session addInput:self.videoDeviceInput];
        }
        
        AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        if ( connection.isVideoStabilizationSupported ) {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
        
        [self.session commitConfiguration];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            [self configureManualHUD];
            
            //            self.cameraButton.enabled = YES;
            self.recordButton.enabled = YES;
            //            self.photoButton.enabled = YES;
            //            self.captureModeControl.enabled = YES;
            self.HUDButton.enabled = YES;
            self.manualHUD.userInteractionEnabled = YES;
        } );
    } );
}

- (IBAction)changeFocusMode:(id)sender
{
    UISegmentedControl *control = sender;
    AVCaptureFocusMode mode = (AVCaptureFocusMode)[self.focusModes[control.selectedSegmentIndex] intValue];
    
    NSError *error = nil;
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        if ( [self.videoDevice isFocusModeSupported:mode] ) {
            self.videoDevice.focusMode = mode;
        }
        else {
            NSLog( @"Focus mode %@ is not supported. Focus mode is %@.", [self stringFromFocusMode:mode], [self stringFromFocusMode:self.videoDevice.focusMode] );
            self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(self.videoDevice.focusMode)];
        }
        [self.videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}
- (IBAction)rescaleLensPositionSliderRange:(UILongPressGestureRecognizer *)sender {
    printf("\nrescaled_value %f to %f\n", (self.lensPositionSlider.value), property_control_value(self.lensPositionSlider.value, 0.f, 1.f, 1.f, 0.f));
    rescale_lens_position = set_lens_position_scale(0.f, 1.f, self.lensPositionSlider.value - 0.10, self.lensPositionSlider.value + 0.10);
    
}

- (IBAction)magnifyLensPositionSlider:(UISlider *)sender forEvent:(UIEvent *)event {
    printf("%s\n", __PRETTY_FUNCTION__);
    // set new colors
//    [sender setMinimumTrackTintColor:[UIColor systemOrangeColor]];
//    [sender setMaximumTrackTintColor:[UIColor systemIndigoColor]];
//    [sender setThumbTintColor:[UIColor systemGrayColor]];
    [sender setBackgroundColor:[UIColor colorWithWhite:1.f alpha:0.15f]];
    
    rescale_lens_position = set_lens_position_scale(0.f, 1.f, (sender.value - 0.10), (sender.value + 0.15));
}

- (IBAction)changeLensPosition:(UISlider *)sender
{
    __autoreleasing NSError *error = nil;
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        [self.videoDevice setFocusModeLockedWithLensPosition:(*rescale_lens_position_t)(sender.value) completionHandler:nil];
        [self.videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}
- (IBAction)restoreLensSlider:(UISlider *)sender forEvent:(UIEvent *)event {
    [self restoreLensSlider_:sender forEvent:event];
}

- (IBAction)restoreLensSlider_:(UISlider *)sender forEvent:(UIEvent *)event {
    printf("%s\n", __PRETTY_FUNCTION__);
    // restore original colors
//    [sender setMinimumTrackTintColor:[UIColor systemYellowColor]];
//    [sender setMaximumTrackTintColor:[UIColor systemBlueColor]];
//    [sender setThumbTintColor:[UIColor whiteColor]];
    [sender setBackgroundColor:[UIColor colorWithWhite:1.f alpha:0.f]];

    rescale_lens_position = set_lens_position_scale(0.f, 1.f, 0.f, 1.f);
}

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *device = self.videoDevice;
        
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            if ( focusMode != AVCaptureFocusModeLocked && device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode] ) {
                device.focusPointOfInterest = point;
                device.focusMode = focusMode;
            }
            
            if ( exposureMode != AVCaptureExposureModeCustom && device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
                device.exposurePointOfInterest = point;
                device.exposureMode = exposureMode;
            }
            
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
            [device unlockForConfiguration];
        }
        else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    } );
}

- (IBAction)changeExposureMode:(id)sender
{
    UISegmentedControl *control = sender;
    AVCaptureExposureMode mode = (AVCaptureExposureMode)[self.exposureModes[control.selectedSegmentIndex] intValue];
    self.exposureDurationSlider.enabled = ( mode == AVCaptureExposureModeCustom );
    self.ISOSlider.enabled = ( mode == AVCaptureExposureModeCustom );
    NSError *error = nil;
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        if ( [self.videoDevice isExposureModeSupported:mode] ) {
            self.videoDevice.exposureMode = mode;
        }
        else {
            NSLog( @"Exposure mode %@ is not supported. Exposure mode is %@.", [self stringFromExposureMode:mode], [self stringFromExposureMode:self.videoDevice.exposureMode] );
            self.exposureModeControl.selectedSegmentIndex = [self.exposureModes indexOfObject:@(self.videoDevice.exposureMode)];
        }
        [self.videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

- (IBAction)changeExposureDuration:(UISlider *)sender
{
    UISlider *control = sender;
    NSError *error = nil;

    double minExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 1000.f), 1000*1000*1000));
    double maxExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 3.f), 1000*1000*1000));
    double exposureDurationSeconds = control_property_value(sender.value, minExposureDurationSeconds, maxExposureDurationSeconds, kExposureDurationPower, 0.f);
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        [self.videoDevice setExposureModeCustomWithDuration:CMTimeMakeWithSeconds( exposureDurationSeconds, 1000*1000*1000 )  ISO:AVCaptureISOCurrent completionHandler:nil];
        [self.videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

- (IBAction)changeTorchLevel:(UISlider *)sender
{
    @try {
        __autoreleasing NSError *error;
        if ([self->_videoDevice lockForConfiguration:&error] && ([[NSProcessInfo processInfo] thermalState] != NSProcessInfoThermalStateCritical || [[NSProcessInfo processInfo] thermalState] != NSProcessInfoThermalStateSerious)) {
            if (sender.value != 0)
                [self->_videoDevice setTorchModeOnWithLevel:sender.value error:&error];
            else
                [self->_videoDevice setTorchMode:AVCaptureTorchModeOff];
        } else {
            NSLog(@"Unable to adjust torch level; thermal state: %lu", [[NSProcessInfo processInfo] thermalState]);
        }
    } @catch (NSException *exception) {
        NSLog(@"AVCaptureDevice lockForConfiguration returned error\t%@", exception);
    } @finally {
        [self->_videoDevice unlockForConfiguration];
    }
}

- (IBAction)changeISO:(UISlider *)sender
{
    NSError *error = nil;
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        @try {
            [self.videoDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:control_property_value(sender.value, self.videoDevice.activeFormat.minISO, self.videoDevice.activeFormat.maxISO, 1.f, 0.f) completionHandler:nil];
        } @catch (NSException *exception) {
            [self.videoDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:AVCaptureISOCurrent completionHandler:nil];
        } @finally {
            
        }
        
        [self.videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}


- (IBAction)changeVideoZoomFactor:(UISlider *)sender {
    if (![self.videoDevice isRampingVideoZoom] && (sender.value != self.videoDevice.videoZoomFactor)) {
        @try {
           ^{
                    NSError * e = nil;
                    ((([self.videoDevice lockForConfiguration:&e] && !e)
                    && ^ unsigned long { [self.videoDevice setVideoZoomFactor:control_property_value(sender.value, self.videoDevice.minAvailableVideoZoomFactor, self.videoDevice.activeFormat.videoMaxZoomFactor, kVideoZoomFactorPowerCoefficient, 0.f)]; return 1UL; }())
                    || ^ unsigned long { @throw [NSException exceptionWithName:e.domain reason:e.localizedFailureReason userInfo:@{@"Error Code" : @(e.code)}]; return 1UL; }());
                }();
        } @catch (NSException * exception) {
            printf("Error configuring camera:\n\tDomain: %s\n\tLocalized failure reason: %s\n\tError code: %lu\n",
                   [exception.name UTF8String],
                   [exception.reason UTF8String],
                   [[exception.userInfo valueForKey:@"Error Code"] unsignedIntegerValue]);
        } @finally {
            [self.videoDevice unlockForConfiguration];
        }
    }
}

- (IBAction)changeWhiteBalanceMode:(id)sender
{
    UISegmentedControl *control = sender;
    AVCaptureWhiteBalanceMode mode = (AVCaptureWhiteBalanceMode)[self.whiteBalanceModes[control.selectedSegmentIndex] intValue];
    NSError *error = nil;
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        if ( [self.videoDevice isWhiteBalanceModeSupported:mode] ) {
            self.videoDevice.whiteBalanceMode = mode;
        }
        else {
            NSLog( @"White balance mode %@ is not supported. White balance mode is %@.", [self stringFromWhiteBalanceMode:mode], [self stringFromWhiteBalanceMode:self.videoDevice.whiteBalanceMode] );
            self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(self.videoDevice.whiteBalanceMode)];
        }
        [self.videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

- (void)setWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains
{
    NSError *error = nil;
    
    if ( [self.videoDevice lockForConfiguration:&error] ) {
        AVCaptureWhiteBalanceGains normalizedGains = [self normalizedGains:gains]; // Conversion can yield out-of-bound values, cap to limits
        [self.videoDevice setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:normalizedGains completionHandler:nil];
        [self.videoDevice unlockForConfiguration];
    }
    else {
        NSLog( @"Could not lock device for configuration: %@", error );
    }
}

- (IBAction)changeTemperature:(id)sender
{
    AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
        .temperature = control_property_value(self.temperatureSlider.value, 3000.f, 8000.f, 1.f, 0.f),
        .tint = control_property_value(self.tintSlider.value, -150.f, 150.f, 1.f, 0.f)
    };
    
    [self setWhiteBalanceGains:[self.videoDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint]];
}

- (IBAction)changeTint:(id)sender
{
    AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
        .temperature = control_property_value(self.temperatureSlider.value, 3000.f, 8000.f, 1.f, 0.f),
        .tint = control_property_value(self.tintSlider.value, -150.f, 150.f, 1.f, 0.f)
    };
    
    [self setWhiteBalanceGains:[self.videoDevice deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint]];
}

- (IBAction)lockWithGrayWorld:(id)sender
{
    [self setWhiteBalanceGains:self.videoDevice.grayWorldDeviceWhiteBalanceGains];
    
    AVCaptureWhiteBalanceTemperatureAndTintValues whiteBalanceTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:self.videoDevice.deviceWhiteBalanceGains];
    self.tintSlider.value = property_control_value(whiteBalanceTemperatureAndTint.tint, -150.f, 150.f, 1.f, 0.f);
    self.temperatureSlider.value = property_control_value(whiteBalanceTemperatureAndTint.temperature, 3000.f, 8000.f, 1.f, 0.f);
}

- (AVCaptureWhiteBalanceGains)normalizedGains:(AVCaptureWhiteBalanceGains)gains
{
    AVCaptureWhiteBalanceGains g = gains;
    
    g.redGain = MAX( 1.0, g.redGain );
    g.greenGain = MAX( 1.0, g.greenGain );
    g.blueGain = MAX( 1.0, g.blueGain );
    
    g.redGain = MIN( self.videoDevice.maxWhiteBalanceGain, g.redGain );
    g.greenGain = MIN( self.videoDevice.maxWhiteBalanceGain, g.greenGain );
    g.blueGain = MIN( self.videoDevice.maxWhiteBalanceGain, g.blueGain );
    
    return g;
}

#pragma mark Recording Movies

- (IBAction)toggleMovieRecording:(UIButton *)sender
{
//    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
//    AVCaptureVideoOrientation previewLayerVideoOrientation = previewLayer.connection.videoOrientation;
    if ( ! self.movieFileOutput.isRecording ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setAlpha:.15];
        });
        
        dispatch_async( self.sessionQueue, ^{
            if ( [UIDevice currentDevice].isMultitaskingSupported ) {
                self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
            }
            AVCaptureConnection *movieConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            movieConnection.videoRotationAngle = self->_previewView.rotation_coordinator.videoRotationAngleForHorizonLevelCapture;
            
            NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
            NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
            [self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
        });
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setAlpha:1.0];
            [(UIButton *)sender setImage:[UIImage systemImageNamed:@"bolt.slash"] forState:UIControlStateSelected];
            
        });
        dispatch_async( self.sessionQueue, ^{
            [self.movieFileOutput stopRecording];
        });
    }
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
    // Enable the Record button to let the user stop the recording
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    // Note that currentBackgroundRecordingID is used to end the background task associated with this recording.
    // This allows a new recording to be started, associated with a new UIBackgroundTaskIdentifier, once the movie file output's isRecording property
    // is back to NO — which happens sometime after this method returns.
    // Note: Since we use a unique file path for each recording, a new recording will not overwrite a recording currently being saved.
    UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    
    dispatch_block_t cleanup = ^{
        if ( [[NSFileManager defaultManager] fileExistsAtPath:outputFileURL.path] ) {
            [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
        }
        
        if ( currentBackgroundRecordingID != UIBackgroundTaskInvalid ) {
            [[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
        }
    };
    
    BOOL success = YES;
    
    if ( error ) {
        NSLog( @"Error occurred while capturing movie: %@", error );
        success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    }
    if ( success ) {
        // Check authorization status
        [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
            if ( status == PHAuthorizationStatusAuthorized ) {
                // Save the movie file to the photo library and cleanup
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    // In iOS 9 and later, it's possible to move the file into the photo library without duplicating the file data.
                    // This avoids using double the disk space during save, which can make a difference on devices with limited free disk space.
                    PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
                    options.shouldMoveFile = YES;
                    PHAssetCreationRequest *changeRequest = [PHAssetCreationRequest creationRequestForAsset];
                    [changeRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
                } completionHandler:^( BOOL success, NSError *error ) {
                    if ( ! success ) {
                        NSLog( @"Could not save movie to photo library: %@", error );
                    }
                    cleanup();
                }];
            }
            else {
                cleanup();
            }
        }];
    }
    else {
        cleanup();
    }
    
    // Enable the Camera and Record buttons to let the user switch camera and start another recording
    dispatch_async( dispatch_get_main_queue(), ^{
        // Only enable the ability to change camera if the device has more than one camera
        //        self.cameraButton.enabled = ( self.videoDeviceDiscoverySession.devices.count > 1 );
        self.recordButton.alpha = 1.0;
        // TO-DO: Change button image to record.circle.fill
        //        [self.recordButton setTitle:NSLocalizedString( @"Record", @"Recording button record title" ) forState:UIControlStateNormal];
        //        self.captureModeControl.enabled = YES;
    });
}

#pragma mark KVO and Notifications

- (void)addObservers
{
    [self addObserver:self forKeyPath:@"session.running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [self addObserver:self forKeyPath:@"videoDevice.focusMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:FocusModeContext];
    [self addObserver:self forKeyPath:@"videoDevice.lensPosition" options:NSKeyValueObservingOptionNew context:LensPositionContext];
    [self addObserver:self forKeyPath:@"videoDevice.exposureMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:ExposureModeContext];
    [self addObserver:self forKeyPath:@"videoDevice.exposureDuration" options:NSKeyValueObservingOptionNew context:ExposureDurationContext];
    [self addObserver:self forKeyPath:@"videoDevice.ISO" options:NSKeyValueObservingOptionNew context:ISOContext];
    [self addObserver:self forKeyPath:@"videoDevice.videoZoomFactor" options:NSKeyValueObservingOptionNew context:VideoZoomFactorContext];
    [self addObserver:self forKeyPath:@"videoDevice.whiteBalanceMode" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:WhiteBalanceModeContext];
    [self addObserver:self forKeyPath:@"videoDevice.deviceWhiteBalanceGains" options:NSKeyValueObservingOptionNew context:DeviceWhiteBalanceGainsContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDevice];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self removeObserver:self forKeyPath:@"session.running" context:SessionRunningContext];
    [self removeObserver:self forKeyPath:@"videoDevice.focusMode" context:FocusModeContext];
    [self removeObserver:self forKeyPath:@"videoDevice.lensPosition" context:LensPositionContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureMode" context:ExposureModeContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureDuration" context:ExposureDurationContext];
    [self removeObserver:self forKeyPath:@"videoDevice.ISO" context:ISOContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureTargetBias" context:ExposureTargetBiasContext];
    [self removeObserver:self forKeyPath:@"videoDevice.exposureTargetOffset" context:ExposureTargetOffsetContext];
    [self removeObserver:self forKeyPath:@"videoDevice.videoZoomFactor" context:VideoZoomFactorContext];
    [self removeObserver:self forKeyPath:@"videoDevice.whiteBalanceMode" context:WhiteBalanceModeContext];
    [self removeObserver:self forKeyPath:@"videoDevice.deviceWhiteBalanceGains" context:DeviceWhiteBalanceGainsContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    id oldValue = change[NSKeyValueChangeOldKey];
    id newValue = change[NSKeyValueChangeNewKey];
    
    if ( context == FocusModeContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureFocusMode newMode = [newValue intValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                self.focusModeControl.selectedSegmentIndex = [self.focusModes indexOfObject:@(newMode)];
                self.lensPositionSlider.enabled = ( newMode == AVCaptureFocusModeLocked );
                self.lensPositionSlider.selected = ( newMode == AVCaptureFocusModeLocked );
                
                if ( oldValue && oldValue != [NSNull null] ) {
                    AVCaptureFocusMode oldMode = [oldValue intValue];
                    NSLog( @"focus mode: %@ -> %@", [self stringFromFocusMode:oldMode], [self stringFromFocusMode:newMode] );
                }
                else {
                    NSLog( @"focus mode: %@", [self stringFromFocusMode:newMode] );
                }
            } );
        }
    }
    else if ( context == LensPositionContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureFocusMode focusMode = self.videoDevice.focusMode;
            float newLensPosition = [newValue floatValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( focusMode != AVCaptureFocusModeLocked ) {
                    self.lensPositionSlider.value = newLensPosition;
                }
                
            } );
        }
    }
    else if ( context == ExposureModeContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureExposureMode newMode = [newValue intValue];
            if ( oldValue && oldValue != [NSNull null] ) {
                AVCaptureExposureMode oldMode = [oldValue intValue];
                
                if ( oldMode != newMode && oldMode == AVCaptureExposureModeCustom ) {
                    NSError *error = nil;
                    if ( [self.videoDevice lockForConfiguration:&error] ) {
                        self.videoDevice.activeVideoMaxFrameDuration = kCMTimeInvalid;
                        self.videoDevice.activeVideoMinFrameDuration = kCMTimeInvalid;
                        [self.videoDevice unlockForConfiguration];
                    }
                    else {
                        NSLog( @"Could not lock device for configuration: %@", error );
                    }
                }
            }
            dispatch_async( dispatch_get_main_queue(), ^{
                
                self.exposureModeControl.selectedSegmentIndex = [self.exposureModes indexOfObject:@(newMode)];
                self.exposureDurationSlider.enabled = ( newMode == AVCaptureExposureModeCustom );
                self.ISOSlider.enabled = ( newMode == AVCaptureExposureModeCustom );
                self.exposureDurationSlider.selected = ( newMode == AVCaptureExposureModeCustom );
                self.ISOSlider.selected = ( newMode == AVCaptureExposureModeCustom );
                
                
                if ( oldValue && oldValue != [NSNull null] ) {
                    AVCaptureExposureMode oldMode = [oldValue intValue];
                    NSLog( @"exposure mode: %@ -> %@", [self stringFromExposureMode:oldMode], [self stringFromExposureMode:newMode] );
                }
                else {
                    NSLog( @"exposure mode: %@", [self stringFromExposureMode:newMode] );
                }
            } );
        }
    }
    else if ( context == ExposureDurationContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            double newDurationSeconds = CMTimeGetSeconds( [newValue CMTimeValue] );
            AVCaptureExposureMode exposureMode = self.videoDevice.exposureMode;
            
            double exposureDurationSeconds = CMTimeGetSeconds( self.videoDevice.exposureDuration );
            double minExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 1000.f), 1000*1000*1000));
            double maxExposureDurationSeconds = CMTimeGetSeconds(CMTimeMakeWithSeconds((1.f / 3.f), 1000*1000*1000));
            
            
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( exposureMode != AVCaptureExposureModeCustom ) {
                    self.exposureDurationSlider.value = property_control_value(exposureDurationSeconds, minExposureDurationSeconds, maxExposureDurationSeconds, kExposureDurationPower, 0.f);
                }
            } );
        }
    }
    else if ( context == ISOContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            float newISO = [newValue floatValue];
            AVCaptureExposureMode exposureMode = self.videoDevice.exposureMode;
            
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( exposureMode != AVCaptureExposureModeCustom ) {
                    self.ISOSlider.value = property_control_value(newISO, self.videoDevice.activeFormat.minISO, self.videoDevice.activeFormat.maxISO, 1.f, 0.f);
                }
            } );
        }
    }
    else if ( context == VideoZoomFactorContext) {
        if ( newValue && newValue != [NSNull null] ) {
            double newZoomFactor = [newValue doubleValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                [self.videoZoomFactorSlider setValue:property_control_value(newZoomFactor, self.videoDevice.minAvailableVideoZoomFactor, self.videoDevice.activeFormat.videoMaxZoomFactor, kVideoZoomFactorPowerCoefficient, -1.f)];
            });
        }
    }
    else if ( context == WhiteBalanceModeContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureWhiteBalanceMode newMode = [newValue intValue];
            dispatch_async( dispatch_get_main_queue(), ^{
                self.whiteBalanceModeControl.selectedSegmentIndex = [self.whiteBalanceModes indexOfObject:@(newMode)];
                self.temperatureSlider.enabled = ( newMode == AVCaptureWhiteBalanceModeLocked );
                self.tintSlider.enabled = ( newMode == AVCaptureWhiteBalanceModeLocked );
                
                if ( oldValue && oldValue != [NSNull null] ) {
                    AVCaptureWhiteBalanceMode oldMode = [oldValue intValue];
                    NSLog( @"white balance mode: %@ -> %@", [self stringFromWhiteBalanceMode:oldMode], [self stringFromWhiteBalanceMode:newMode] );
                }
            } );
        }
    }
    else if ( context == DeviceWhiteBalanceGainsContext ) {
        if ( newValue && newValue != [NSNull null] ) {
            AVCaptureWhiteBalanceGains newGains;
            [newValue getValue:&newGains];
            AVCaptureWhiteBalanceTemperatureAndTintValues newTemperatureAndTint = [self.videoDevice temperatureAndTintValuesForDeviceWhiteBalanceGains:newGains];
            AVCaptureWhiteBalanceMode whiteBalanceMode = self.videoDevice.whiteBalanceMode;
            dispatch_async( dispatch_get_main_queue(), ^{
                if ( whiteBalanceMode != AVCaptureExposureModeLocked ) {
                    self.temperatureSlider.value = property_control_value(newTemperatureAndTint.temperature, 3000.f, 8000.f, 1.f, 0.f);
                    self.tintSlider.value = property_control_value(newTemperatureAndTint.tint, -150.f, 150.f, 1.f, 0.f);
                }
            });
        }
    }
    else if ( context == SessionRunningContext ) {
        BOOL isRunning = NO;
        if ( newValue && newValue != [NSNull null] ) {
            isRunning = [newValue boolValue];
        }
        dispatch_async( dispatch_get_main_queue(), ^{
            //            self.cameraButton.enabled = isRunning && ( self.videoDeviceDiscoverySession.devices.count > 1 );
            self.recordButton.enabled = isRunning;
        } );
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
    [self focusWithMode:self.videoDevice.focusMode exposeWithMode:self.videoDevice.exposureMode atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog( @"Capture session runtime error: %@", error );
    
    if ( error.code == AVErrorMediaServicesWereReset ) {
        dispatch_async( self.sessionQueue, ^{
            // If we aren't trying to resume the session, try to restart it, since it must have been stopped due to an error (see -[resumeInterruptedSession:])
            if ( self.isSessionRunning ) {
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            }
            else {
                dispatch_async( dispatch_get_main_queue(), ^{
                    self.resumeButton.hidden = NO;
                } );
            }
        } );
    }
    else {
        self.resumeButton.hidden = NO;
    }
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
    NSLog( @"Capture session was interrupted with reason %ld", (long)reason );
    
    if ( reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
        reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
        // Simply fade-in a button to enable the user to try to resume the session running
        self.resumeButton.hidden = NO;
        self.resumeButton.alpha = 0.0;
        [UIView animateWithDuration:0.25 animations:^{
            self.resumeButton.alpha = 1.0;
        }];
    }
    else if ( reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
        // Simply fade-in a label to inform the user that the camera is unavailable
        self.cameraUnavailableImageView.hidden = NO;
        self.cameraUnavailableImageView.alpha = 0.0;
        [UIView animateWithDuration:0.25 animations:^{
            self.cameraUnavailableImageView.alpha = 1.0;
        }];
    }
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog( @"Capture session interruption ended" );
    
    if ( ! self.resumeButton.hidden ) {
        [UIView animateWithDuration:0.25 animations:^{
            self.resumeButton.alpha = 0.0;
        } completion:^( BOOL finished ) {
            self.resumeButton.hidden = YES;
        }];
    }
    if ( ! self.cameraUnavailableImageView.hidden ) {
        [UIView animateWithDuration:0.25 animations:^{
            self.cameraUnavailableImageView.alpha = 0.0;
        } completion:^( BOOL finished ) {
            self.cameraUnavailableImageView.hidden = YES;
        }];
    }
}

- (NSString *)stringFromFocusMode:(AVCaptureFocusMode)focusMode
{
    NSString *string = @"INVALID FOCUS MODE";
    
    if ( focusMode == AVCaptureFocusModeLocked ) {
        string = @"Locked";
    }
    else if ( focusMode == AVCaptureFocusModeAutoFocus ) {
        string = @"Auto";
    }
    else if ( focusMode == AVCaptureFocusModeContinuousAutoFocus ) {
        string = @"ContinuousAuto";
    }
    
    return string;
}

- (NSString *)stringFromExposureMode:(AVCaptureExposureMode)exposureMode
{
    NSString *string = @"INVALID EXPOSURE MODE";
    
    if ( exposureMode == AVCaptureExposureModeLocked ) {
        string = @"Locked";
    }
    else if ( exposureMode == AVCaptureExposureModeAutoExpose ) {
        string = @"Auto";
    }
    else if ( exposureMode == AVCaptureExposureModeContinuousAutoExposure ) {
        string = @"ContinuousAuto";
    }
    else if ( exposureMode == AVCaptureExposureModeCustom ) {
        string = @"Custom";
    }
    
    return string;
}

- (NSString *)stringFromWhiteBalanceMode:(AVCaptureWhiteBalanceMode)whiteBalanceMode
{
    NSString *string = @"INVALID WHITE BALANCE MODE";
    
    if ( whiteBalanceMode == AVCaptureWhiteBalanceModeLocked ) {
        string = @"Locked";
    }
    else if ( whiteBalanceMode == AVCaptureWhiteBalanceModeAutoWhiteBalance ) {
        string = @"Auto";
    }
    else if ( whiteBalanceMode == AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance ) {
        string = @"ContinuousAuto";
    }
    
    return string;
}

@end
