//
//  VideoClip.h
//  irtc
//
//  Created by ideawu on 3/5/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VideoClip : NSObject

@property (readonly) double duration;
@property (readonly) double startTime;
@property (readonly) double endTime;
@property (readonly) int frameCount;
@property (readonly) BOOL hasIFrame;

@property NSData *sps;
@property NSData *pps;
@property NSMutableArray *frames;

+ (VideoClip *)clipFromData:(NSData *)data;


- (NSData *)data;

- (void)reset;
- (void)appendFrame:(NSData *)frames pts:(double)pts;

@end
