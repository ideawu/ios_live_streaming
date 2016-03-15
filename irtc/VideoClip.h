//
//  VideoClip.h
//  irtc
//
//  Created by ideawu on 3/5/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface VideoClip : NSObject

@property (readonly) double duration;
@property (readonly) double startTime;
@property (readonly) double endTime;
@property (readonly) int frameCount;
@property (readonly) double frameDuration;
@property (readonly) BOOL hasKeyFrame;

@property (readonly) double nextFramePTS;

/**
 SPS without header
 */
@property NSData *sps;
/**
 PPS without header
 */
@property NSData *pps;

/**
 AVCC 格式, 一个或者多个 NALU
 */
- (void)appendFrame:(NSData *)frame pts:(double)pts;

/**
 AVCC 格式
 作为 Reader 的时候使用
 */
- (NSData *)nextFrame:(double *)pts;

/**
 生成 Annex-B 格式的流
 */
- (NSData *)data;
- (void)parseData:(NSData *)data;

@end
