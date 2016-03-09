//
//  VideoRecorder.m
//  irtc
//
//  Created by ideawu on 3/4/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoRecorder.h"
#import "VideoClip.h"
#import "VideoEncoder.h"

@interface VideoRecorder()<AVCaptureVideoDataOutputSampleBufferDelegate>{
	AVCaptureDevice *videoDevice;
	AVCaptureDeviceInput *videoInput;
	AVCaptureVideoDataOutput* _videoDataOutput;
	
	dispatch_queue_t _captureQueue;
	dispatch_queue_t _processQueue;

	double _pts_start;
	double _pts_end;
	
	VideoClip *_clip;
	void (^_clipCallback)(VideoClip *clip);

	NSData *_sps;
	NSData *_pps;

	int _prevPOC;
}
@property (nonatomic) VideoEncoder* encoder;
@end

@implementation VideoRecorder

- (id)init{
	self = [super init];
	_width = 340;
	_height = 480;
	_bitrate = 400 * 1024;
	_clipDuration = 0.3;
	_prevPOC = -1;
	[self setupDevices];
	return self;
}

- (void)start:(void (^)(VideoClip *clip))callback{
	_clipCallback = callback;
	
	_encoder = [VideoEncoder encoderForHeight:_height andWidth:_width bitrate:_bitrate];
	[_encoder encodeWithBlock:^void(NSArray *frames, double pts) {
		[self processFrames:frames pts:pts];
	} onParams:^(NSData *sps, NSData *pps) {
		[self processSps:sps pps:pps];
	}];
	
	[_session startRunning];
}

- (void)stop{
	[_session stopRunning];
	[_encoder shutdown];
}

- (void)setupDevices{
	NSError *error = nil;
	_captureQueue = dispatch_queue_create("capture", DISPATCH_QUEUE_SERIAL);
	_processQueue = dispatch_queue_create("process", DISPATCH_QUEUE_SERIAL);
	
	_session = [[AVCaptureSession alloc] init];
	[_session setSessionPreset:AVCaptureSessionPreset640x480];

	videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	for(AVCaptureDevice *dev in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]){
		if(dev.position == AVCaptureDevicePositionFront){
			videoDevice = dev;
			break;
		}
	}
	videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];

	_videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	[_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
	NSDictionary* settings = @{
							   (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
							   };
	_videoDataOutput.videoSettings = settings;

	[_session beginConfiguration];
	[_session addOutput:_videoDataOutput];
	[_session addInput:videoInput];
	[_session commitConfiguration];
	
#if TARGET_OS_IPHONE
	[self setVideoOrientation:(AVCaptureVideoOrientation)[UIApplication sharedApplication].statusBarOrientation];
#endif
}

- (void)setVideoOrientation:(AVCaptureVideoOrientation)orientation{
	AVCaptureConnection *connection =[_videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
	if([connection videoOrientation ]) {
		[connection setVideoOrientation:(AVCaptureVideoOrientation)orientation];
	}
}

- (void)processSps:(NSData *)sps pps:(NSData *)pps{
	_sps = sps;
	_pps = pps;
	
	NSMutableString *desc = [[NSMutableString alloc] init];
	[desc appendString:@"sps:"];
	for(int i=0; i<_sps.length; i++){
		unsigned char c = ((const unsigned char *)_sps.bytes)[i];
		[desc appendFormat:@" %02x", c];
	}
	[desc appendString:@" pps:"];
	for(int i=0; i<_pps.length; i++){
		unsigned char c = ((const unsigned char *)_pps.bytes)[i];
		[desc appendFormat:@" %02x", c];
	}
	NSLog(@"%@", desc);
}

- (void)processFrames:(NSArray *)frames pts:(double)pts{
	//NSLog(@"pts: %.3f", pts);
	if(!_clip){
		_clip = [[VideoClip alloc] init];
		_clip.sps = _sps;
		_clip.pps = _pps;
	}
	for (NSData *data in frames){
		[_clip appendFrame:data pts:pts];
	}
	if(_clip.duration >= _clipDuration){
		if(_clipCallback){
			_clipCallback(_clip);
		}
		_clip = nil;
	}
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

// TODO: 如果能保证正确性, 可以改为 NO, 提高性能
- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput{
	return YES;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
	[_encoder encodeSampleBuffer:sampleBuffer];
}


@end
