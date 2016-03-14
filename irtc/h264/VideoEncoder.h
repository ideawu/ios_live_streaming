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
 SPS with AVCC header
 */
@property (readonly) NSData *sps;
/**
 PPS with AVCC header
 */
@property (readonly) NSData *pps;

/**
 AVCC 格式, 只有一个 NALU
 */
- (void)start:(void (^)(NSData *nalu, double pts, double duration))callback;
- (void)shutdown;

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer pts:(double)pts duration:(double)duration;

@end
