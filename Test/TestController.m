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
	AVSampleBufferDisplayLayer *videoLayer;
	VideoRecorder *_recorder;
}

@end

@implementation TestController

- (void)windowDidLoad {
    [super windowDidLoad];
	_videoView.layer.backgroundColor = [NSColor blackColor].CGColor;

	// create our AVSampleBufferDisplayLayer and add it to the view
	videoLayer = [[AVSampleBufferDisplayLayer alloc] init];
	videoLayer.frame = self.videoView.frame;
	videoLayer.bounds = self.videoView.bounds;
	videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;

	// set Timebase, you may need this if you need to display frames at specific times
	// I didn't need it so I haven't verified that the timebase is working
	CMTimebaseRef controlTimebase;
	CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase);

	//videoLayer.controlTimebase = controlTimebase;
	CMTimebaseSetTime(videoLayer.controlTimebase, kCMTimeZero);
	CMTimebaseSetRate(videoLayer.controlTimebase, 1.0);

	[[self.videoView layer] addSublayer:videoLayer];


	VideoPlayer *player = [[VideoPlayer alloc] init];
	player.videoLayer = videoLayer;
	[player play];

	_recorder = [[VideoRecorder alloc] init];

	[_recorder start:^(VideoClip *clip) {
		NSData *data = clip.data;
		NSLog(@"%2d frames[%.3f ~ %.3f], duration: %.3f, %5d bytes, has_key_frame: %@",
			  clip.frameCount, clip.startTime, clip.endTime, clip.duration, (int)data.length,
			  clip.hasKeyFrame?@"yes":@"no");

		VideoClip *c = [VideoClip clipFromData:data];
		[player addClip:c];
	}];


}

@end
