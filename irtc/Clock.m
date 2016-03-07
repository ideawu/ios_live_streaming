//
//  Clock.m
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "Clock.h"

@implementation Clock

- (id)init{
	self = [super init];
	_speed = 1;
	[self reset];
	return self;
}

- (void)reset{
	_now = -1;
	_tick_zero = -1;
}

- (double)speed{
	return _speed;
}

- (void)setSpeed:(double)speed{
	if(speed < 0){
		return;
	}
	_speed = speed;
	_change_speed_tick = _tick_last;
}

- (void)tick:(double)real_tick{
	_tick_last = real_tick;
	if(_tick_zero == -1){
		_tick_zero = real_tick;
		_change_speed_tick = _tick_last;
	}
	double df = _speed * (real_tick - _change_speed_tick);
	_now =  df + (_change_speed_tick - _tick_zero);
}

@end
