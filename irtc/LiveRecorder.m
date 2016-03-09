//
//  LiveRecorder.m
//  irtc
//
//  Created by ideawu on 3/9/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoClip.h"
#import "LiveRecorder.h"
#import "AudioEncoder.h"
#import "VideoEncoder.h"

@interface LiveRecorder ()<AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>{
	AVCaptureDeviceInput *_audioInput;
	AVCaptureDeviceInput *_videoInput;
	AVCaptureAudioDataOutput* _audioDataOutput;
	AVCaptureVideoDataOutput* _videoDataOutput;
	
	dispatch_queue_t _captureQueue;
	dispatch_queue_t _processQueue;
	
	NSData *_sps;
	NSData *_pps;
	VideoClip *_videoClip;
}
@property (nonatomic) AVCaptureDevice *audioDevice;
@property (nonatomic) AVCaptureDevice *videoDevice;
@property (nonatomic, copy) void (^audioCallback)(NSData *data);
@property (nonatomic, copy) void (^videoCallback)(VideoClip *clip);

@property (nonatomic) VideoEncoder *videoEncoder;
@property (nonatomic) AudioEncoder *audioEncoder;

@end


@implementation LiveRecorder

- (id)init{
	self = [super init];
	_clipDuration = 0.3;
	[self setupSession];
	return self;
}

- (void)setupSession{
	if(_session){
		return;
	}
	_session = [[AVCaptureSession alloc] init];
	[_session setSessionPreset:AVCaptureSessionPreset640x480];
	
	_captureQueue = dispatch_queue_create("capture", DISPATCH_QUEUE_SERIAL);
	_processQueue = dispatch_queue_create("process", DISPATCH_QUEUE_SERIAL);
}

- (void)setupAudio:(void (^)(NSData *data))callback{
	if(_audioDevice){
		return;
	}
	_audioCallback = callback;

	NSError *error = nil;
	_audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
	for(AVCaptureDevice *dev in [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]){
		if(dev.position == AVCaptureDevicePositionFront){
			_audioDevice = dev;
			break;
		}
	}
	_audioInput = [AVCaptureDeviceInput deviceInputWithDevice:_audioDevice error:&error];

	_audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
	[_audioDataOutput setSampleBufferDelegate:self queue:_captureQueue];

	[_session beginConfiguration];
	[_session addOutput:_audioDataOutput];
	[_session addInput:_audioInput];
	[_session commitConfiguration];
}

- (void)setupVideo:(void (^)(VideoClip *clip))callback{
	if(_videoDevice){
		return;
	}
	_videoCallback = callback;
	
	NSError *error = nil;
	_videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	for(AVCaptureDevice *dev in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]){
		if(dev.position == AVCaptureDevicePositionFront){
			_videoDevice = dev;
			break;
		}
	}
	_videoInput = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
	
	_videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	[_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
	NSDictionary* settings = @{
							   (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
							   };
	_videoDataOutput.videoSettings = settings;
	
	[_session beginConfiguration];
	[_session addOutput:_videoDataOutput];
	[_session addInput:_videoInput];
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

- (void)start{
	__weak typeof(self) me = self;
	if(_audioDevice){
		_audioEncoder = [[AudioEncoder alloc] init];
		[_audioEncoder encodeWithBlock:^(NSData *data, double pts) {
			NSLog(@"%d bytes, pts: %.3f", (int)data.length, pts);
		}];
	}
	if(_videoDevice){
		double _width = 340;
		double _height = 480;
		double _bitrate = 400 * 1024;
		
		_videoEncoder = [VideoEncoder encoderForHeight:_height andWidth:_width bitrate:_bitrate];
		[_videoEncoder encodeWithBlock:^void(NSArray *frames, double pts) {
			[me onVideoFrames:frames pts:pts];
		} onParams:^(NSData *sps, NSData *pps) {
			[me onVideoSps:sps pps:pps];
		}];
	}
	
	[_session startRunning];
}

- (void)stop{
	[_session stopRunning];
	[_audioEncoder shutdown];
	[_videoEncoder shutdown];
	_audioEncoder = nil;
	_videoEncoder = nil;
}

#pragma mark - Audio Encoder callbacks


#pragma mark - Video Encoder callbacks

- (void)onVideoSps:(NSData *)sps pps:(NSData *)pps{
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

- (void)onVideoFrames:(NSArray *)frames pts:(double)pts{
	//NSLog(@"pts: %.3f", pts);
	if(!_videoClip){
		_videoClip = [[VideoClip alloc] init];
		_videoClip.sps = _sps;
		_videoClip.pps = _pps;
	}
	for (NSData *data in frames){
		[_videoClip appendFrame:data pts:pts];
	}
	if(_videoClip.duration >= _clipDuration){
		if(_videoCallback){
			_videoCallback(_videoClip);
		}
		_videoClip = nil;
	}
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

// TODO: 如果能保证正确性, 可以改为 NO, 提高性能
- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput{
	return YES;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
	if(captureOutput == _audioDataOutput){
		[_audioEncoder encodeSampleBuffer:sampleBuffer];
	}
	if(captureOutput == _videoDataOutput){
		[_videoEncoder encodeSampleBuffer:sampleBuffer];
	}
}

@end
