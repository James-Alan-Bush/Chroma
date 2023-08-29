//
//  AppDelegate.h
//  Chroma
//
//  Created by Xcode Developer on 8/29/23.
//

@import Foundation;
@import UIKit;
@import AVFoundation;

@protocol MovieAppEventDelegate <NSObject>

@property (nonatomic) AVCaptureMovieFileOutput * movieFileOutput;
- (IBAction)toggleMovieRecording:(id)sender;


@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>

+ (AppDelegate *)sharedAppDelegate;




@property (nonatomic) UIWindow *window;
@property (weak) IBOutlet id<MovieAppEventDelegate> movieAppEventDelegate;



@end

