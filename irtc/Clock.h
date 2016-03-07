//
//  Clock.h
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Clock : NSObject{
	double _tick_zero;
	double _tick_last;
	double _speed;
	double _change_speed_tick;
}
@property (nonatomic, readonly) double now;
// default: 1.0
@property (nonatomic) double speed;

- (void)reset;
- (void)tick:(double)real_tick;

@end
