//
//  TestRecorder.m
//  irtc
//
//  Created by ideawu on 3/15/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "TestRecorder.h"
#import "LiveRecorder.h"

@interface TestRecorder(){
	LiveRecorder *_recorder;
}
@end


@implementation TestRecorder

- (id)init{
	self = [super init];
	[self run];
	return self;
}

- (void)run{
	_recorder = [[LiveRecorder alloc] init];
	_recorder.width = 640;
	_recorder.height = 480;
	[_recorder setupVideo:^(VideoClip *clip){
		//
	}];
	[_recorder start];
}

@end
