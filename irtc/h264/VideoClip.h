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
@property (readonly) BOOL hasIFrame;

@property (readonly) double nextFramePTS;

@property NSData *sps;
@property NSData *pps;
@property NSMutableArray *frames;

+ (VideoClip *)clipFromData:(NSData *)data;

- (NSData *)data;

- (void)reset;
- (void)appendFrame:(NSData *)frames pts:(double)pts;

- (NSData *)nextFrame:(double *)pts;

@end
