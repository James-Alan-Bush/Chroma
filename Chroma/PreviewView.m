//
//  PreviewView.m
//  ChromaBeta
//
//  Created by Xcode Developer on 8/29/23.
//

#import "PreviewView.h"

@import AVFoundation;

@interface PreviewView ()

@end

@implementation PreviewView

- (void)awakeFromNib {
    [super awakeFromNib];
    
    @try {
        [self.capture_session beginConfiguration];
        [self.capture_session setSessionPreset:AVCaptureSessionPreset3840x2160];
        [self.capture_session setAutomaticallyConfiguresCaptureDeviceForWideColor:TRUE];
        ([self.capture_session canAddInput:self.video_input])
        ? ^{
            [self.capture_session addInput:self.video_input];
            
            __autoreleasing NSError *error = nil;
            [self.video_device lockForConfiguration:&error];
            
            @try {
                [self.video_device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                [self.video_device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            } @catch (NSException *exception) {
                NSLog(@"Error setting focus mode: %@", error.description);
            } @finally {
                
                @try {
                    [self.video_device setAutomaticallyEnablesLowLightBoostWhenAvailable:TRUE];
                } @catch (NSException *exception) {
                    NSLog(@"Error setting focus mode: %@", error.description);
                } @finally {
                    
                    @try {
                        [self.video_device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                        [self.video_device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                    } @catch (NSException *exception) {
                        NSLog(@"Error setting focus mode: %@", error.description);
                    } @finally {
                        [self.video_device unlockForConfiguration];
                    }
                }
            }
        }()
        : ^{
            NSException* exception = [NSException
                                      exceptionWithName:@"Cannot add device input to capture session"
                                      reason:@"Capture session cannot add device input"
                                      userInfo:@{@"Error Code" : @(CaptureSessionSetupResultFailed)}];
            @throw exception;
        }();
    } @catch (NSException * exception) {
        printf("Exception configuring capture session:\n\t%s\n\t%s\n\t%lu",
               [exception.name UTF8String],
               [exception.reason UTF8String],
               ((NSNumber *)[exception.userInfo valueForKey:@"Error Code"]).unsignedLongValue);
    } @finally {
        [self.capture_session commitConfiguration];
    }
}

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)capture_session
{
    return ((AVCaptureVideoPreviewLayer *)self.layer).session;
}

- (void)setCapture_session:(AVCaptureSession *)session
{
    ((AVCaptureVideoPreviewLayer *)self.layer).session = session;
}

- (const AVCaptureDeviceInput *)video_input {
    __autoreleasing NSError * error;
    const AVCaptureDeviceInput * di = [AVCaptureDeviceInput deviceInputWithDevice:self.video_device error:&error];
    return di;
}

- (void)setVideo_input:(AVCaptureDeviceInput *)input {
    self.video_input = input;
}

- (const AVCaptureDevice *)video_device
{
    const AVCaptureDevice * cd = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    return cd;
}

- (void)setVideo_device:(AVCaptureDevice *)device
{
    self.video_device = device;
}

- (AVCaptureDeviceRotationCoordinator *)rotation_coordinator
{
    AVCaptureDeviceRotationCoordinator * rc = [[AVCaptureDeviceRotationCoordinator alloc] initWithDevice:self.video_device previewLayer:(AVCaptureVideoPreviewLayer *)self.layer];
    ((AVCaptureVideoPreviewLayer *)self.layer).connection.videoRotationAngle = rc.videoRotationAngleForHorizonLevelCapture;
    return rc;
}

- (void)setRotation_coordinator:(AVCaptureDeviceRotationCoordinator *)rotation_coordinator
{
    self.rotation_coordinator = rotation_coordinator;
}

@end
