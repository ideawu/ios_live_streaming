//
//  ViewController.m
//  ios
//
//  Created by ideawu on 12/4/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "ViewController.h"
#import "IKit/IKit.h"
#import "VideoPlayer.h"
#import "LiveStream.h"

@interface ViewController (){
	LiveStream *_stream;
}
@property IView *mainView;
@property IView *videoView;

@property CALayer *videoLayer;
@property VideoPlayer *player;

@property IInput *ipInput;
@property IButton *submit;

@property NSString *ip;

@end


@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.title = @"Player";

	_mainView = [IView namedView:@"main"];
	_videoView = [_mainView getViewById:@"video"];
	[self addIViewRow:_mainView];
	[self reload];
	[_mainView layoutIfNeeded];
	
	__weak typeof(self) me = self;
	_ipInput = (IInput *)[_mainView getViewById:@"ip"];
	_submit = (IButton *)[_mainView getViewById:@"submit"];
	
	[_submit bindEvent:IEventClick handler:^(IEventType event, IView *view) {
		[me start];
	}];
	
	[self loadIp];
}

- (void)start{
	if(_videoLayer){
		return;
	}
	//_submit.button.enabled = NO;
	[self loadIp];

	_videoLayer = [[CALayer alloc] init];
	_videoLayer.frame = self.videoView.bounds;
	_videoLayer.bounds = self.videoView.bounds;
	_videoLayer.borderWidth = 1;
	_videoLayer.borderColor = [UIColor blueColor].CGColor;
	
	_videoView.layer.backgroundColor = [UIColor blackColor].CGColor;
	[[self.videoView layer] addSublayer:_videoLayer];

	_player = [[VideoPlayer alloc] init];
	_player.layer = _videoLayer;

	[_player play];

	NSString *url = [NSString stringWithFormat:@"http://%@:8100/stream", _ip]; // icomet
	_stream = [[LiveStream alloc] init];
	[_stream sub:url callback:^(NSData *data) {
		VideoClip *clip = [VideoClip clipFromData:data];
		NSLog(@"%2d frames[%.3f ~ %.3f], duration: %.3f, %5d bytes, key_frame: %@",
			  clip.frameCount, clip.startTime, clip.endTime, clip.duration, (int)data.length,
			  clip.hasKeyFrame?@"yes":@"no");

		[_player addClip:clip];
	}];
}

- (void)loadIp{
	_ip = _ipInput.value;
	if(!_ip || _ip.length == 0){
		_ip = [[NSUserDefaults standardUserDefaults] objectForKey:@"ip"];
		if(!_ip || _ip.length == 0){
			_ip = @"127.0.0.1";
		}
	}
	[[NSUserDefaults standardUserDefaults] setObject:_ip forKey:@"ip"];
	_ipInput.value = _ip;
}

@end
