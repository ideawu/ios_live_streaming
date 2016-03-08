//
//  VideoPlayer.h
//  irtc
//
//  Created by ideawu on 16-3-6.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "VideoClip.h"

@interface VideoPlayer : NSObject

@property CALayer *layer;

- (void)play;
//- (void)pause;
//- (void)stop;

- (void)setSpeed:(double)speed;

- (void)addClip:(VideoClip *)clip;

@end
