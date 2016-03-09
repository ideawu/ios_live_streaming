//
//  LiveRecorder.h
//  irtc
//
//  Created by ideawu on 3/9/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import "VideoClip.h"

@interface LiveRecorder : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;
@property(nonatomic) double clipDuration;

- (void)setupAudio:(void (^)(NSData *data))callback;
- (void)setupVideo:(void (^)(VideoClip *clip))callback;

- (void)start;

@end
