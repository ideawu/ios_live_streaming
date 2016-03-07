//
//  PlayerItem.m
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "PlayerItem.h"

typedef enum{
	ClipStatusNone = 0,
	ClipStatusReading,
	ClipStatusCompleted,
}ClipStatus;

@interface PlayerItem(){
	ClipStatus _status;
}
@end


@implementation PlayerItem

- (id)init{
	self = [super init];
	_status = ClipStatusNone;
	return self;
}

- (BOOL)isReading{
	return _status == ClipStatusReading;
}

- (BOOL)isCompleted{
	return _status == ClipStatusCompleted;
}

- (void)startSessionAtSourceTime:(double)time{
	_status = ClipStatusReading;
	_sessionStartTime = time;
}

- (BOOL)hasNextFrameForTime:(double)time{
	double elapse = time - _sessionStartTime;
	if(elapse > _clip.duration){
		return YES;
	}
	
	double maxAhead = -MIN(0.01, _clip.frameDuration/4);
	double expect = _clip.nextFramePTS - _clip.startTime + _sessionStartTime;
	double delay = time - expect;
	//NSLog(@"  time: %.3f expect: %.3f, delay: %+.3f, frameDuration: %.3f", time, expect, delay, _clip.frameDuration);
	if(delay >= 0){
		return YES;
	}else if(delay >= maxAhead){
		return YES;
	}
	return NO;
}

- (NSData *)nextFrame{
	double pts;
	NSData *frame = [_clip nextFrame:&pts];
	if(!frame){
		_status = ClipStatusCompleted;
	}
	return frame;
}

@end
