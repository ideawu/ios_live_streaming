//
//  VideoRecorder.h
//  irtc
//
//  Created by ideawu on 3/4/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import "VideoClip.h"



@interface VideoRecorder : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;
@property (nonatomic) double clipDuration;
@property (nonatomic) double width;
@property (nonatomic) double height;
@property (nonatomic) double bitrate;

- (void)start:(void (^)(VideoClip *clip))callback;
- (void)stop;

@end
