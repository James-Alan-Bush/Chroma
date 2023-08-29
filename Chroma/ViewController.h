//
//  ViewController.h
//  Chroma
//
//  Created by Xcode Developer on 8/29/23.
//


@import UIKit;

#import "AppDelegate.h"

// Scales standardized slider value (0 - 1) to actual camera property value (ranges vary)
// From slider to camera property
static double (^ _Nonnull control_property_value)(double, double, double, double, double) = ^ double (double control_value, double property_value_min, double property_value_max, double gamma, double offset) {
    return ((pow(control_value, gamma) * (property_value_max - property_value_min)) + property_value_min);
};

// Standardizes (0 - 1) camera property values (ranges vary)
// From camera property to slider
static double (^ _Nonnull property_control_value)(double, double, double, double, double) = ^ double (double property_value, double property_value_min, double property_value_max, double inverse_gamma, double offset) {
    return pow((property_value - property_value_min) / (property_value_max - property_value_min), 1.f / inverse_gamma); //((pow(property_value, 1.f / inverse_gamma) - (property_value_min / property_value_max)) - property_value_min);
};

// Unused
static double (^ _Nonnull rescale_value)(double, double, double, double, double) = ^ double (double value, double value_min, double value_max, double new_value_min, double new_value_max) {
    return (new_value_max - new_value_min) * (value - value_min) / (value_max - value_min) + new_value_min;
};


static const double (^ _Nonnull rescale_lens_position)(double);
static const typeof(rescale_lens_position) * _Nullable rescale_lens_position_t = &rescale_lens_position;
static double (^_Nonnull(^ _Nonnull set_lens_position_scale)(const double, const double, const double, const double))(double) = ^ (double value_min, double value_max, double new_value_min, double new_value_max) {
    return ^ (double value) {
        return (new_value_max - new_value_min) * (value - value_min) / (value_max - value_min) + new_value_min;
    };
};

@class AppDelegate;

@interface ViewController : UIViewController <MovieAppEventDelegate, UIGestureRecognizerDelegate>

@property (nonatomic) AVCaptureMovieFileOutput * _Nullable movieFileOutput;
- (void)captureOutput:(AVCaptureFileOutput * _Nullable)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL * _Nonnull)outputFileURL fromConnections:(NSArray * _Nonnull)connections error:(NSError * _Nullable)error;

- (IBAction)toggleMovieRecording:(id _Nonnull)sender;

@property (weak, nonatomic) IBOutlet UISegmentedControl * _Null_unspecified manualHUDSegmentedControl;

@end
