//
//  Clock.h
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VideoPlayerState : NSObject{
}
// 播放器时间
@property (nonatomic, readonly) double time;
// 影片时间(相对时间)
@property (nonatomic, readonly) double movieTime;
// 影片时间(绝对时间), 用于音频和视频的同步
@property (nonatomic, readonly) double pts;
// default: 1.0
@property (nonatomic) double speed;

@property double frameDuration;
@property int frameCount;

- (void)reset;
- (void)tick:(double)tick;

- (BOOL)isStarting;
- (BOOL)isPaused;
- (BOOL)isPlaying;

- (void)start;
- (void)pause;
- (void)play;

- (double)delay;
- (double)nextFrameTime;
- (BOOL)isReadyForNextFrame;
- (void)displayFramePTS:(double)pts;

@end
