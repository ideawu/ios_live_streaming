//
//  Clock.m
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "PlayerState.h"

typedef enum{
	PlayerStateNone,
	PlayerStateStopped = PlayerStateNone,
	PlayerStatePaused,
	PlayerStateStarting,
	PlayerStatePlaying,
}PlayerStateState;

@interface PlayerState(){
	double _last_tick;
	double _speed;
	PlayerStateState _state;
}
@end


@implementation PlayerState

- (id)init{
	self = [super init];
	_speed = 1;
	_state = PlayerStateNone;
	[self reset];
	return self;
}

- (void)reset{
	_time = 0;
	_last_tick = -1;
}

- (double)speed{
	return _speed;
}

- (void)setSpeed:(double)speed{
	if(speed < 0){
		return;
	}
	_speed = speed;
}

- (void)tick:(double)tick{
	if(_last_tick == -1){
		_time = 0;
		_last_tick = tick;
	}
	if(_state == PlayerStatePlaying){
		_time += _speed * (tick - _last_tick);
	}
	_last_tick = tick;
}

- (BOOL)isPlaying{
	return _state == PlayerStatePlaying;
}

- (void)pause{
	_state = PlayerStatePaused;
}

- (void)resume{
	if(_state == PlayerStatePaused || _state == PlayerStateStarting){
		_state = PlayerStatePlaying;
	}
}

- (double)delay{
	return _time - self.nextFrameTime;
}

- (void)nextFrame{
	_frameCount ++;
}

- (double)nextFrameTime{
	return _frameCount * _frameDuration;
}

- (BOOL)readyForNextFrame{
	if(!self.isPlaying){
		return NO;
	}
	double maxAhead = -MIN(0.01, _frameDuration/4);
	double delay = self.delay;
	//NSLog(@"  time: %.3f expect: %.3f, delay: %+.3f, frameDuration: %.3f",
	//		time, self.nextFrameTime, delay, _frameDuration);
	if(delay >= 0){
		return YES;
	}else if(delay >= maxAhead){
		return YES;
	}
	return NO;
}

@end
