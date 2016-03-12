//
//  TestController.m
//  irtc
//
//  Created by ideawu on 16-3-5.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "TestController.h"
#import <AVFoundation/AVFoundation.h>
#import "LiveRecorder.h"
#import "VideoPlayer.h"
#import "AudioPlayer.h"
#import "AudioDecoder.h"

@interface TestController (){
	CALayer *_videoLayer;
	LiveRecorder *_recorder;
	VideoPlayer *_player;
	AudioPlayer *_audioPlayer;
	AudioDecoder *_audioDecoder;
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


	__weak typeof(self) me = self;

	_recorder = [[LiveRecorder alloc] init];
	_recorder.clipDuration = 0.2;
	//_recorder.bitrate = 800 * 1024;

//	_player = [[VideoPlayer alloc] init];
//	_player.layer = _videoLayer;
//	[_player play];
//
//	[_recorder setupVideo:^(VideoClip *clip) {
//		NSData *data = clip.data;
//		NSLog(@"%2d frames[%.3f ~ %.3f], duration: %.3f, %5d bytes, key_frame: %@",
//			  clip.frameCount, clip.startTime, clip.endTime, clip.duration, (int)data.length,
//			  clip.hasKeyFrame?@"yes":@"no");
//		
//		VideoClip *c = [VideoClip clipFromData:data];
//		[_player addClip:c];
//	}];

	int raw_format = 1;
	if(raw_format){
		_audioPlayer = [[AudioPlayer alloc] init];
		[_audioPlayer setSampleRate:44100 channels:2];
	}else{
		_audioPlayer = [AudioPlayer AACPlayerWithSampleRate:44100 channels:2];
	}

	_audioDecoder = [[AudioDecoder alloc] init];
	[_audioDecoder start:^(NSData *pcm, double duration) {
		[_audioPlayer appendData:pcm];
	}];

	[_recorder setupAudio:^(NSData *data, double pts, double duration) {
		int i = [me incr];
		if(i > 130 && i < 350){
			//NSLog(@"return %d", i);
			return;
		}
		NSLog(@"%d bytes, %f %f", (int)data.length, pts, duration);
		if(raw_format){
			[_audioDecoder decode:data];
		}else{
			[_audioPlayer appendData:data];
		}
	}];
	
	[_recorder start];
}

- (int)incr{
	static int i = 0;
	return i++;
}

@end
