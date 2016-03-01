//
//  LiveRecorder.m
//  recorder
//
//  Created by ideawu on 16-2-28.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>
#import "LiveRecorder.h"
#import "LiveClipWriter.h"

typedef enum{
	RecordNone,
	RecordStart,
	RecordRunning,
	RecordStop,
}RecordStatus;

@interface LiveRecorder ()<AVCaptureVideoDataOutputSampleBufferDelegate>{
	AVCaptureDevice *videoDevice;
	AVCaptureDevice *audioDevice;
	AVCaptureDeviceInput *videoInput;
	AVCaptureDeviceInput *audioInput;
	AVCaptureVideoDataOutput* _videoDataOutput;

	dispatch_queue_t _captureQueue;
	dispatch_queue_t _processQueue;

	int _recordSeq;
	RecordStatus _status;

	NSMutableArray *_workingWriters;

	void (^_chunkCallback)(NSData *);
}
@property (nonatomic) int width;
@property (nonatomic) int height;
@end

@implementation LiveRecorder

- (id)init{
	self = [super init];
	_status = RecordNone;
	_chunkDuration = 1;
	_chunkCallback = nil;
	_width = 360;
	_height = 480;
	[self setupDevices];
	return self;
}

+ (LiveRecorder *)recorderForWidth:(int)width height:(int)height{
	LiveRecorder *ret = [[LiveRecorder alloc] init];
	ret.width = width;
	ret.height = height;
	return ret;
}


- (void)setupDevices{
	_captureQueue = dispatch_queue_create("capture", DISPATCH_QUEUE_SERIAL);
	_processQueue = dispatch_queue_create("process", DISPATCH_QUEUE_SERIAL);

	_session = [[AVCaptureSession alloc] init];

	_videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	[_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
	NSDictionary* setcapSettings = @{
									 (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
									 };
	_videoDataOutput.videoSettings = setcapSettings;

	NSError *error = nil;
	videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	for(AVCaptureDevice *dev in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]){
		if(dev.position == AVCaptureDevicePositionFront){
			videoDevice = dev;
			break;
		}
	}
	videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	for(AVCaptureDevice *dev in [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]){
		if(dev.position == AVCaptureDevicePositionFront){
			audioDevice = dev;
			break;
		}
	}
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
	[_session addInput:videoInput];
	[_session addInput:audioInput];
	[_session commitConfiguration];

#if TARGET_OS_IPHONE
	[self setVideoOrientation:[UIApplication sharedApplication].statusBarOrientation];
#endif
}

- (void)setVideoOrientation:(AVCaptureVideoOrientation)orientation{
	AVCaptureConnection *connection =[_videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
	if([connection videoOrientation ]) {
		[connection setVideoOrientation:(AVCaptureVideoOrientation)orientation];
	}
}

- (void)start:(void (^)(NSData *))chunkCallback{
	if(_status != RecordNone){
		NSLog(@"already started");
		return;
	}
	_status = RecordStart;
	_chunkCallback = chunkCallback;

	_workingWriters = [[NSMutableArray alloc] init];

	for(int i=0; i<3; i++){
		[self createRecorder];
	}
	[_session startRunning];

	// 必须在 startRunning 之后才能修改 activeFormat, 操!
//	NSError *error = nil;
//	if ([videoDevice lockForConfiguration:&error]) {
//		for(AVCaptureDeviceFormat *deviceFormat in [videoDevice formats] ){
//			NSLog(@"%@", deviceFormat);
//		}
//		[videoDevice unlockForConfiguration];
//	}
}

- (void)stop{
	_status = RecordStop;
	[_session stopRunning];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

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
		[rec encodeVideoSampleBuffer:sampleBuffer];

		if(rec.duration >= _chunkDuration){
			[self switchClip];
		}
	}
}

// in capture queue
- (void)switchClip{
	LiveClipWriter *rec = _workingWriters.firstObject;
	[_workingWriters removeObjectAtIndex:0];

	[rec finishWritingWithCompletionHandler:^(NSData *data){
		dispatch_async(_processQueue, ^{
			if(_chunkCallback){
				_chunkCallback(data);
			}

			[self createRecorder];
		});
	}];
}

- (NSString *)nextFilename{
	NSString *name = [NSString stringWithFormat:@"m%03d.mp4", _recordSeq];
	if(++_recordSeq >= 9){
		_recordSeq = 0;
	}
	return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

// called in process thread
- (void)createRecorder{
	//NSLog(@"create recorder: %d", _recordSeq);
	NSString *filename = [self nextFilename];
	LiveClipWriter *rec = [[LiveClipWriter alloc] initWithFilename:filename videoWidth:_width videoHeight:_height];
	dispatch_async(_captureQueue, ^{
		[_workingWriters addObject:rec];
	});
}

@end
