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
#import "IObj/Http.h"

@interface ViewController (){
	NSMutableArray *_chunks;
	BOOL _uploading;
}

@property LiveRecorder *recorder;
@property AVCaptureVideoPreviewLayer *previewLayer;
@property IView *mainView;
@property IView *videoView;

@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.title = @"Recorder";

	_chunks = [[NSMutableArray alloc] init];
	_uploading = false;

	_recorder = [LiveRecorder recorderForWidth:360 height:480];
	_recorder.chunkDuration = 0.5;

	NSString *xml = @""
	"<div style=\"width: 100%; height: 100%; background: #fff;\">"
	"	<div id=\"video\" style=\"width: 240; height: 320; background: #333;\">"
	"	</div>"
	"	<span style=\"width: 100%; clear: both; text-align: center; color: #333;\">Hello World!</span>"
	"</div>";
	_mainView = [IView viewFromXml:xml];
	_videoView = [_mainView getViewById:@"video"];
	[self.view addSubview:_mainView];
	[_mainView layoutIfNeeded];

	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_recorder.session];
	_previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	[_previewLayer setFrame:[_videoView bounds]];
	[_videoView.layer addSublayer:_previewLayer];

	__weak typeof(self) me = self;
	[_recorder start:^(NSData *data) {
		[me onChunkReady:data];
	}];
}

static NSString *base64_encode_data(NSData *data){
	data = [data base64EncodedDataWithOptions:0];
	NSString *ret = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	return ret;
}

// 注意! _chunks 变量只能在 main queue 中操作!
- (void)onChunkReady:(NSData *)data{
	// http 请求必须放在 main queue
	dispatch_async(dispatch_get_main_queue(), ^{
		[_chunks addObject:data];
		[self uploadChunk];
	});
}

- (void)uploadChunk{
	dispatch_async(dispatch_get_main_queue(), ^{
		if(_uploading){
			return;
		}
		NSData *data = _chunks.firstObject;
		if(!data){
			return;
		}

		NSString *url = @"http://192.168.0.100:8000/push"; // icomet
		NSString *data_str = base64_encode_data(data);
		NSDictionary *params = @{
								 @"content" : data_str,
								 };
		_uploading = YES;
		http_post_raw(url, params, ^(NSData *data) {
			NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			NSLog(@"uploaded, resp: %@", str);

			_uploading = NO;
			[_chunks removeObjectAtIndex:0];
			if(_chunks.count > 0){
				[self uploadChunk];
			}
		});
	});
}

@end
