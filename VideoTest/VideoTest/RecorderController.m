//
//  RecorderController.m
//  VideoTest
//
//  Created by ideawu on 12/16/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "RecorderController.h"
#import "LiveClipWriter.h"
#import "LivePlayer.h"
#import "Http.h"

typedef enum{
	RecordNone,
	RecordStart,
	RecordRunning,
	RecordStop,
}RecordStatus;

@interface RecorderController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>{
	AVCaptureAudioPreviewOutput *audioPreviewOutput;
	AVCaptureDevice *videoDevice;
	AVCaptureDevice *audioDevice;
	AVCaptureDeviceInput *videoInput;
	AVCaptureDeviceInput *audioInput;
	AVCaptureVideoDataOutput* _videoDataOutput;
	AVCaptureAudioDataOutput* _audioDataOutput;

	dispatch_queue_t _captureQueue;
	dispatch_queue_t _processQueue;
	
	int _recordSeq;
	RecordStatus _status;
	
	NSMutableArray *_workingWriters;
	NSMutableArray *_finishingWriters;
	NSMutableArray *_completedWriters;
	
	LivePlayer *_livePlayer;
	
}
@property AVCaptureSession *session;
@property AVCaptureVideoPreviewLayer *previewLayer;
@end

@implementation RecorderController

- (id)initWithWindowNibName:(NSString *)windowNibName{
	NSLog(@"%s", __func__);
	self = [super initWithWindowNibName:windowNibName];
	
	_status = RecordNone;
	[self setupDevices];
	
	return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
	
	_livePlayer = [[LivePlayer alloc] init];
	
	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
	[_previewLayer setFrame:[_previewView bounds]];
	[_previewLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
	[_previewView.layer setBackgroundColor:[NSColor blackColor].CGColor];
	[_previewView.layer addSublayer:_previewLayer];
	
	[_session startRunning];

	/*
	// 必须在 startRunning 之后才能修改 activeFormat, 操!
	NSError *error = nil;
	if ([videoDevice lockForConfiguration:&error]) {
		for(AVCaptureDeviceFormat *deviceFormat in [videoDevice formats] ){
			if([deviceFormat.description rangeOfString:@"640"].length > 0){
				NSLog(@"%@", deviceFormat);
				[videoDevice setActiveFormat:deviceFormat];
				break;
			}
		}
		[videoDevice unlockForConfiguration];
	}
	*/
}

- (void)windowWillClose:(NSNotification *)notification{
	[[self session] stopRunning];
}

- (void)setupDevices{
	NSError *error = nil;
	
	_captureQueue = dispatch_queue_create("capture", DISPATCH_QUEUE_SERIAL);
	_processQueue = dispatch_queue_create("process", DISPATCH_QUEUE_SERIAL);
	
	_session = [[AVCaptureSession alloc] init];

	_videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	[_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
	NSDictionary* setcapSettings = @{
		(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
	};
	_videoDataOutput.videoSettings = setcapSettings;

	_audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
	[_audioDataOutput setSampleBufferDelegate:self queue:_captureQueue];
	
	videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
	
	for(AVFrameRateRange *range in videoDevice.activeFormat.videoSupportedFrameRateRanges){
		float setFPS = 24.0;
		if(range.minFrameRate <= setFPS && range.maxFrameRate >= setFPS){
			if([videoDevice lockForConfiguration:nil]){
				videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, setFPS);
				videoDevice.activeVideoMaxFrameDuration = CMTimeMake(1, setFPS);
				[videoDevice unlockForConfiguration];
				break;
			}
		}
	}
	
	[_session beginConfiguration];
	[_session setSessionPreset:AVCaptureSessionPresetMedium];
	[_session addOutput:_videoDataOutput];
	[_session addOutput:_audioDataOutput];
	[_session addInput:videoInput];
	[_session addInput:audioInput];
	[_session commitConfiguration];
}

- (IBAction)start:(id)sender {
	if(_status != RecordNone){
		NSLog(@"already started");
		return;
	}
	NSLog(@"NSTemporaryDirectory: %@", NSTemporaryDirectory());
		  
	_workingWriters = [[NSMutableArray alloc] init];
	_finishingWriters = [[NSMutableArray alloc] init];
	_completedWriters = [[NSMutableArray alloc] init];
	
	for(int i=0; i<3; i++){
		[self createRecorder];
	}

	_status = RecordStart;
}

- (IBAction)stop:(id)sender {
	_status = RecordStop;
}

- (NSString *)getVideoFilename:(int)seq{
	NSString *name = [NSString stringWithFormat:@"m%03d.mp4", seq];
	return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (void)createRecorder{
	NSLog(@"create recorder: %d", _recordSeq);
	NSString *filename = [self getVideoFilename:_recordSeq++];
	LiveClipWriter *rec = [[LiveClipWriter alloc] initWithFilename:filename];
	[_workingWriters addObject:rec];
	if(_recordSeq >= 10){
		_recordSeq = 0;
	}
}

- (void)processCompletedClip{
	LiveClipWriter *rec = _completedWriters.firstObject;
	if(!rec){
		return;
	}
	[_completedWriters removeObjectAtIndex:0];
	[self createRecorder];
	
	// TODO:
	[self uploadClip:rec];
	NSLog(@"processed %@", rec.writer.outputURL.lastPathComponent);
}

static NSString *base64_encode_data(NSData *data){
	data = [data base64EncodedDataWithOptions:0];
	NSString *ret = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	return ret;
}

- (void)uploadClip:(LiveClipWriter *)rec{
	NSString *url = @"http://127.0.0.1:8000/push"; // icomet
	NSData *data = [NSData dataWithContentsOfURL:rec.writer.outputURL];
	if(data == nil){
		NSLog(@"nil data");
		return;
	}
	NSString *data_str = base64_encode_data(data);
	NSDictionary *params = @{
							 @"content" : data_str,
							 };
	http_post(url, params, ^(NSData *data) {
		NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		NSLog(@"uploaded %@, resp: %@", rec.writer.outputURL.lastPathComponent, str);
	});
}

- (void)switchClip{
	LiveClipWriter *rec = _workingWriters.firstObject;
	[_finishingWriters addObject:rec];
	[_workingWriters removeObjectAtIndex:0];

	[rec finishWritingWithCompletionHandler:^{
		dispatch_async(_captureQueue, ^{
			for(LiveClipWriter *tmp in _finishingWriters){
				// retain tmp first, because removeObject will invalid iterator
				LiveClipWriter *rec = tmp;
				if(rec.writer.status == AVAssetWriterStatusCompleted){
					[_finishingWriters removeObject:rec];
					[_completedWriters addObject:rec];
					dispatch_async(_processQueue, ^{
						[self processCompletedClip];
					});
				}else if(rec.writer.status == AVAssetWriterStatusFailed || rec.writer.status == AVAssetWriterStatusCancelled){
					NSLog(@"asset writer failed: %@", rec.writer.outputURL);
					[_finishingWriters removeObject:rec];
				}else{
					break;
				}
			}
			
//			// TEST
//			if(_completedWriters.count == 3){
//				CMTime stime, etime;
//				double duration = 0;
//				int frames = 0;
//				
//				stime = ((LiveClipRecorder *)_completedWriters.firstObject).startTime;
//				etime = ((LiveClipRecorder *)_completedWriters.lastObject).endTime;
//				for(LiveClipRecorder *rec in _completedWriters){
//					duration += rec.duration;
//					frames += rec.frameCount;
//				}
//				NSLog(@"recorder, stime: %f, etime: %f, frames: %d, duration: %f", CMTimeGetSeconds(stime), CMTimeGetSeconds(etime), frames, duration);
//				
//				
//				duration = 0;
//				for(LiveClipRecorder *rec in _completedWriters){
//					LiveAVPlayerItem *item = [LiveAVPlayerItem playerItemWithURL:rec.writer.outputURL];
//					duration += item.duration;
//					item = nil;
//				}
//				NSLog(@"items, duration: %f", duration);
//			}
		});
	}];
}

- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput{
	return YES;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
	if(_status == RecordStart){
		_status = RecordRunning;
	}else if(_status == RecordStop){
		_status = RecordNone;
		[self switchClip];
	}
	
	if(_status == RecordRunning){
		LiveClipWriter *rec = _workingWriters.firstObject;
		if(!rec){
			// TODO:
			NSLog(@"no recorder available!");
			_status = RecordNone;
			return;
		}
		if(captureOutput == _videoDataOutput){
			[rec encodeVideoSampleBuffer:sampleBuffer];
		}else{
			[rec encodeAudioSampleBuffer:sampleBuffer];
		}
		
		float chunk_duration = 3.5;
		if(rec.duration >= chunk_duration){
			[self switchClip];
			// TODO: TEST
			//_status = RecordNone;
		}
	}
}

@end
