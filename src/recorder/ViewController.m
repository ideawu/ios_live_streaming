//
//  ViewController.m
//  recorder
//
//  Created by ideawu on 16-2-28.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>

#import "ViewController.h"
#import "LiveRecorder.h"
#import "IKit/IKit.h"

@interface ViewController ()

@property LiveRecorder *recorder;
@property AVCaptureVideoPreviewLayer *previewLayer;
@property IView *mainView;
@property IView *videoView;

@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.title = @"Recorder";

	_recorder = [[LiveRecorder alloc] init];

	NSString *xml = @""
	"<div style=\"width: 100%; height: 100%; background: #fff;\">"
	"	<div id=\"video\" style=\"width: 240; height: 320; background: #333;\">"
	"	</div>"
	"	<span style=\"width: 100%; color: #333;\">Hello World!</span>"
	"</div>";
	_mainView = [IView viewFromXml:xml];
	_videoView = [_mainView getViewById:@"video"];
	[self.view addSubview:_mainView];
	[_mainView layoutIfNeeded];

	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_recorder.session];
	[_previewLayer setFrame:[_videoView bounds]];
	[_videoView.layer addSublayer:_previewLayer];

	[_recorder start:nil];
}

@end
