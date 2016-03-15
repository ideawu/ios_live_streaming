//
//  LiveCapture.h
//  irtc
//
//  Created by ideawu on 3/15/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

@interface LiveCapture : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;

- (void)setupAudio:(void (^)(CMSampleBufferRef sampleBuffer))callback;
- (void)setupVideo:(void (^)(CMSampleBufferRef sampleBuffer))callback;

- (void)start;
- (void)stop;

@end
