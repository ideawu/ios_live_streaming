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

@interface VideoRecorder : NSObject

@property (nonatomic, readonly) AVCaptureSession *session;

- (void)start;

@end
