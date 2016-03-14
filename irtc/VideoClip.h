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
 SPS with start_code or AVCC header, depends on setter/appendFrame
 */
@property NSData *sps;
/**
 PPS with start_code or AVCC header, depends on setter/appendFrame
 */
@property NSData *pps;

/**
 Annex-B 格式的流
 */
+ (VideoClip *)clipFromData:(NSData *)data;

/**
 Annex-B 格式的流
 */
- (NSData *)data;

- (void)reset;

/**
 AVCC/Annex-B 格式, 只有一个 NALU
 */
- (void)appendFrame:(NSData *)nalu pts:(double)pts;

/**
 Annex-B 格式
 作为 Reader 的时候使用
 */
- (NSData *)nextFrame:(double *)pts;

@end
