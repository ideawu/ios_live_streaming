//
//  VideoEncoder.h
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface VideoEncoder : NSObject

/**
 SPS without header
 */
@property (readonly) NSData *sps;
/**
 PPS without header
 */
@property (readonly) NSData *pps;

/**
 AVCC 格式的一个或者多个 NALU
 */
- (void)start:(void (^)(NSData *nalus, double pts, double duration))callback;
- (void)shutdown;

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer pts:(double)pts duration:(double)duration;

@end
