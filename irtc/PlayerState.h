//
//  Clock.h
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PlayerState : NSObject{
}
@property (nonatomic, readonly) double time;
// default: 1.0
@property (nonatomic) double speed;

@property double frameDuration;
@property int frameCount;

- (void)reset;
- (void)tick:(double)tick;

- (BOOL)isPlaying;

- (void)pause;
- (void)resume;

- (double)delay;
- (double)nextFrameTime;
- (BOOL)readyForNextFrame;
- (void)nextFrame;

@end
