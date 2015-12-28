//
//  LiveClipReader.h
//  VideoTest
//
//  Created by ideawu on 12/20/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LiveClipReader : NSObject

@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) double delay;
@property (nonatomic, readonly) int frameCount;
@property (nonatomic, readonly) double frameDuration;
@property (nonatomic, readonly) double startTime;
@property (nonatomic, readonly) double endTime;
@property (nonatomic, readonly) double duration;

+ (LiveClipReader *)clipReaderWithURL:(NSURL *)url;

- (BOOL)isReading;
- (BOOL)isCompleted;

- (void)startSessionAtSourceTime:(double)time;
- (BOOL)hasNextFrameForTime:(double)time;
- (CGImageRef)copyNextFrameForTime:(double)time;

@end
