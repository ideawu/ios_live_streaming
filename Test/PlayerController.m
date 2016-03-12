//
//  PlayerController.m
//  VideoTest
//
//  Created by ideawu on 12/11/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import "PlayerController.h"
#import <AVFoundation/AVFoundation.h>
#import "VideoPlayer.h"
#import "LiveStream.h"

@interface PlayerController (){
	BOOL _playing;
	LiveStream *_stream;
}
@property CALayer *videoLayer;
@property VideoPlayer *player;
@end

@implementation PlayerController

- (void)windowDidLoad {
    [super windowDidLoad];
	
	_videoLayer = [[CALayer alloc] init];
	_videoLayer.frame = self.videoView.bounds;
	_videoLayer.bounds = self.videoView.bounds;
	_videoLayer.borderWidth = 1;
	_videoLayer.borderColor = [NSColor blueColor].CGColor;

	_videoView.layer.backgroundColor = [NSColor blackColor].CGColor;
	[[self.videoView layer] addSublayer:_videoLayer];

	_player = [[VideoPlayer alloc] init];
	_player.layer = _videoLayer;

	[_player play];

	NSString *url = [NSString stringWithFormat:@"http://%@:8100/stream", @"127.0.0.1"]; // icomet
	_stream = [[LiveStream alloc] init];
	[_stream sub:url callback:^(NSData *data) {
		VideoClip *clip = [VideoClip clipFromData:data];
		NSLog(@"%2d frames[%.3f ~ %.3f], duration: %.3f, %5d bytes, key_frame: %@",
			  clip.frameCount, clip.startTime, clip.endTime, clip.duration, (int)data.length,
			  clip.hasKeyFrame?@"yes":@"no");

		[_player addClip:clip];
		if(clip.hasKeyFrame){
			NSLog(@"%@ %@", clip.sps, clip.pps);
		}
	}];
}

- (void)windowWillClose:(NSNotification *)notification{
	_playing = NO;
}

- (IBAction)onPlay:(id)sender {
	NSLog(@"%s", __func__);
	_playing = YES;
}

- (IBAction)onLoad:(id)sender {
	//[_livePlayer addMovieFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"m002.mp4"]];
	//[_livePlayer addMovieFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"m003.mp4"]];
}

- (IBAction)onNextFrame:(id)sender {
}

- (IBAction)onNextSkip:(id)sender {
	for(int i=0; i<10; i++){
//		[_livePlayer nextFrame];
	}
}

- (IBAction)prevFrame:(id)sender {
//	[_livePlayer prevFrame];
}

- (IBAction)onPrevSkip:(id)sender {
	for(int i=0; i<10; i++){
//		[_livePlayer prevFrame];
	}
}

@end
