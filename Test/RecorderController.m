//
//  RecorderController.m
//  VideoTest
//
//  Created by ideawu on 12/16/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "RecorderController.h"
#import "LiveRecorder.h"
#import "IObj/Http.h"

typedef enum{
	RecordNone,
	RecordStart,
	RecordRunning,
	RecordStop,
}RecordStatus;

@interface RecorderController (){
	RecordStatus _status;
	NSMutableArray *_chunks;
	BOOL _uploading;
}
@property LiveRecorder *recorder;
@property AVCaptureVideoPreviewLayer *previewLayer;
@end

@implementation RecorderController

- (id)initWithWindowNibName:(NSString *)windowNibName{
	NSLog(@"%s", __func__);
	self = [super initWithWindowNibName:windowNibName];
	
	_status = RecordNone;
	
	_chunks = [[NSMutableArray alloc] init];
	_uploading = false;
	
	return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
	_videoView.layer.backgroundColor = [NSColor blackColor].CGColor;
}

- (void)windowWillClose:(NSNotification *)notification{
	//[[self session] stopRunning];
}

- (IBAction)start:(id)sender {
	if(_status != RecordNone){
		NSLog(@"already started");
		return;
	}
	NSLog(@"NSTemporaryDirectory: %@", NSTemporaryDirectory());
	_status = RecordStart;

	_recorder = [LiveRecorder recorderForWidth:360 height:480];
	_recorder.chunkDuration = 0.5;
	
	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_recorder.session];
	_previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
	[_previewLayer setFrame:[_videoView bounds]];
	[_videoView.layer addSublayer:_previewLayer];
	
	__weak typeof(self) me = self;
	[_recorder start:^(NSData *data) {
		[me onChunkReady:data];
	}];
}

- (IBAction)stop:(id)sender {
	_status = RecordStop;
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
		
		NSString *ip = @"127.0.0.1";
		NSString *url = [NSString stringWithFormat:@"http://%@:8000/push", ip]; // icomet
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
