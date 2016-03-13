//
//  VideoEncoder.h
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface VideoEncoder : NSObject

@property (readonly) NSData *sps;
@property (readonly) NSData *pps;

- (void)start:(void (^)(NSData *h264, double pts, double duration))callback;
- (void)shutdown;

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
