//
//  PreviewView.h
//  ChromaBeta
//
//  Created by Xcode Developer on 8/29/23.
//

@import UIKit;
@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM( long, CaptureSessionSetupResult ) {
    CaptureSessionSetupResultSuccess,
    CaptureSessionSetupResultCameraNotAuthorized,
    CaptureSessionSetupResultFailed
};

@class AVCaptureSession;

@interface PreviewView : UIView

@property (nonatomic) AVCaptureSession                   * capture_session;
@property (nonatomic) AVCaptureDeviceRotationCoordinator * rotation_coordinator;

@property (nonatomic) AVCaptureDevice                    * video_device;
@property (nonatomic) AVCaptureDeviceInput               * video_input;
@property (nonatomic) AVCaptureDevice                    * audio_device;
@property (nonatomic) AVCaptureDeviceInput               * audio_input;

@end

NS_ASSUME_NONNULL_END
