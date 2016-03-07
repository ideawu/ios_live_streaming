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

@interface PlayerController (){
	BOOL _playing;
}
@property AVSampleBufferDisplayLayer *videoLayer;
@property VideoPlayer *player;
@end

@implementation PlayerController

- (void)windowDidLoad {
    [super windowDidLoad];
	_videoView.layer.backgroundColor = [NSColor blackColor].CGColor;

	_videoLayer = [[AVSampleBufferDisplayLayer alloc] init];
	_videoLayer.frame = self.videoView.frame;
	_videoLayer.bounds = self.videoView.bounds;
	_videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;

	[_videoView.layer addSublayer:_videoLayer];
	
	_player = [[VideoPlayer alloc] init];
	_player.videoLayer = _videoLayer;

	[_player play];
	
	[self onLoad:nil];
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
