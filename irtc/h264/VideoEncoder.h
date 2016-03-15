//
//  VideoEncoder.h
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface VideoEncoder : NSObject

@property (nonatomic) int width;
@property (nonatomic) int height;

/**
 SPS without header
 */
@property (nonatomic, readonly) NSData *sps;
/**
 PPS without header
 */
@property (nonatomic, readonly) NSData *pps;

/**
 AVCC 格式的一个或者多个 NALU
 */
- (void)start:(void (^)(NSData *frame, double pts, double duration))callback;
- (void)shutdown;

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer pts:(double)pts duration:(double)duration;

@end
