//
//  LiveRecorder.h
//  irtc
//
//  Created by ideawu on 3/9/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "VideoClip.h"

@interface LiveRecorder : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;
@property (nonatomic) double clipDuration;
@property (nonatomic) int width;
@property (nonatomic) int height;

- (void)setupAudio:(void (^)(NSData *data, double pts, double duration))callback;
- (void)setupVideo:(void (^)(VideoClip *clip))callback;

- (void)start;
- (void)stop;

@end
