//
//  LiveClipReader.h
//  VideoTest
//
//  Created by ideawu on 12/20/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface LiveClipReader : NSObject

@property (nonatomic, readonly) double delay;
@property (nonatomic, readonly) int frameCount;
@property (nonatomic, readonly) double frameDuration;
@property (nonatomic, readonly) double startTime;
@property (nonatomic, readonly) double endTime;
@property (nonatomic, readonly) double duration;

@property AudioFilePacketTableInfo audioInfo;
@property AudioStreamBasicDescription audioFormat;
@property NSData *audioData;
@property (nonatomic, readonly) double audioDuration;
@property (nonatomic, readonly) int audioFrameCount;

+ (LiveClipReader *)clipReaderWithURL:(NSURL *)url;

- (BOOL)isReading;
- (BOOL)isCompleted;

- (void)startSessionAtSourceTime:(double)time;

- (BOOL)hasNextFrameForTime:(double)time;
// 调用者负责释放内存
- (CGImageRef)copyNextFrameForTime:(double)time;

- (NSData *)audioData;

@end
