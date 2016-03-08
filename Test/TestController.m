//
//  TestController.m
//  irtc
//
//  Created by ideawu on 16-3-5.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "TestController.h"
#import <AVFoundation/AVFoundation.h>
#import "VideoRecorder.h"
#import "VideoPlayer.h"

@interface TestController (){
	CALayer *_videoLayer;
	VideoRecorder *_recorder;
}

@end

@implementation TestController

- (void)windowDidLoad {
    [super windowDidLoad];

	_videoLayer = [[CALayer alloc] init];
	_videoLayer.frame = self.videoView.bounds;
	_videoLayer.bounds = self.videoView.bounds;

	[[self.videoView layer] addSublayer:_videoLayer];
	_videoView.layer.backgroundColor = [NSColor blackColor].CGColor;


	VideoPlayer *player = [[VideoPlayer alloc] init];
	player.layer = _videoLayer;
	[player play];

	_recorder = [[VideoRecorder alloc] init];
	_recorder.clipDuration = 0.2;
	_recorder.bitrate = 800 * 1024;

	[_recorder start:^(VideoClip *clip) {
		NSData *data = clip.data;
		NSLog(@"%2d frames[%.3f ~ %.3f], duration: %.3f, %5d bytes, key_frame: %@",
			  clip.frameCount, clip.startTime, clip.endTime, clip.duration, (int)data.length,
			  clip.hasKeyFrame?@"yes":@"no");

		VideoClip *c = [VideoClip clipFromData:data];
		[player addClip:c];
	}];


}

@end
