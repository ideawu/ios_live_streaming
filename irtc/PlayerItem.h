//
//  PlayerItem.h
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VideoClip.h"

@interface PlayerItem : NSObject

@property VideoClip *clip;
@property (readonly) double sessionStartTime;

- (BOOL)isReading;
- (BOOL)isCompleted;

- (void)startSessionAtSourceTime:(double)time;
- (BOOL)hasNextFrameForTime:(double)time;
- (NSData *)nextFrame;

@end
