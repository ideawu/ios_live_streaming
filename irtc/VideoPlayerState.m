//
//  Clock.m
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoPlayerState.h"

typedef enum{
	PlayerStateNone,
	PlayerStateStopped = PlayerStateNone,
	PlayerStatePaused,
	PlayerStateStarting,
	PlayerStatePlaying,
}PlayerStateState;

@interface VideoPlayerState(){
	double _last_tick;
	double _speed;
	PlayerStateState _state;
	double _nextFrameTime;
	double _first_pts;
}
@end


@implementation VideoPlayerState

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
	_nextFrameTime = 0;
	_first_pts = -1;
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

- (BOOL)isStarting{
	return _state == PlayerStateStarting;
}

- (BOOL)isPaused{
	return _state == PlayerStatePaused;
}

- (void)start{
	_state = PlayerStateStarting;
}

- (void)pause{
	_state = PlayerStatePaused;
}

- (void)play{
	if(_state == PlayerStatePaused || _state == PlayerStateStarting){
		_state = PlayerStatePlaying;
	}
}

- (double)delay{
	return _time - self.nextFrameTime;
}

- (double)movieTime{
	return _pts - _first_pts;
}

- (void)displayFramePTS:(double)pts{
	_frameCount ++;
	if(_first_pts == -1){
		_first_pts = pts;
	}
	_pts = pts;
	_nextFrameTime = _pts - _first_pts + _frameDuration;
	//_nextFrameTime += _frameDuration;
}

- (double)nextFrameTime{
	return _nextFrameTime;
}

- (BOOL)isReadyForNextFrame{
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
