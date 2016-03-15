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
#import "VideoReader.h"

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
@property (nonatomic, copy) void (^audioCallback)(NSData *data, double pts, double duration);
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

- (void)setupAudio:(void (^)(NSData *data, double pts, double duration))callback{
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
	
#if !TARGET_OS_IPHONE
	// 如果不设置这个属性, 在 Mac 下会失败, 因为 AudioConverter 好像只能处理这种 PCM.
	NSDictionary *settings = @{
							   AVFormatIDKey: @(kAudioFormatLinearPCM),
							   AVLinearPCMBitDepthKey: @(16),
							   AVLinearPCMIsFloatKey : @(NO),
							   AVLinearPCMIsNonInterleaved: @(NO),
							   // AVSampleRateKey: @(44100), // not for MAC
							   };
	_audioDataOutput.audioSettings = settings;
#endif

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
		[_audioEncoder start:^(NSData *data, double pts, double duration) {
			[me onAudioChunk:data pts:pts duration:duration];
		}];
	}
	if(_videoDevice){
		// TODO:
//		double _width = 480;
//		double _height = 640;
//		double _bitrate = 400 * 1024;
	
		_videoEncoder = [[VideoEncoder alloc] init];
		[_videoEncoder start:^(NSData *frame, double pts, double duration) {
//			log_debug(@"encoded, pts: %f, duration: %f, %d bytes", pts, duration, (int)frame.length);
			[me onVideoFrame:frame pts:pts];
		}];
	}
	
	[_session startRunning];
	// TEST
//	[self performSelectorInBackground:@selector(fileCapture) withObject:nil];
}

- (void)fileCapture{
	while(1){
		NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/m1.mp4"];
		VideoReader *reader = [[VideoReader alloc] initWithFile:file];
		CMSampleBufferRef sampleBuffer;
		while(1){
			sampleBuffer = [reader nextSampleBuffer];
			if(!sampleBuffer){
				break;
			}
			
			[_videoEncoder encodeSampleBuffer:sampleBuffer];
			
			CFRelease(sampleBuffer);
			usleep(20 * 1000);
		}
	}
}

- (void)stop{
	[_session stopRunning];
	[_audioEncoder shutdown];
	[_videoEncoder shutdown];
	_audioEncoder = nil;
	_videoEncoder = nil;
}

#pragma mark - Audio Encoder callbacks

- (void)onAudioChunk:(NSData *)data pts:(double)pts duration:(double)duration{
	// TODO: build AudioClip
	if(_audioCallback){
		_audioCallback(data, pts, duration);
	}
}

#pragma mark - Video Encoder callbacks

//- (void)onVideoSps:(NSData *)sps pps:(NSData *)pps{
//	_sps = sps;
//	_pps = pps;
//	
//	NSMutableString *desc = [[NSMutableString alloc] init];
//	[desc appendString:@"sps:"];
//	for(int i=0; i<_sps.length; i++){
//		unsigned char c = ((const unsigned char *)_sps.bytes)[i];
//		[desc appendFormat:@" %02x", c];
//	}
//	[desc appendString:@" pps:"];
//	for(int i=0; i<_pps.length; i++){
//		unsigned char c = ((const unsigned char *)_pps.bytes)[i];
//		[desc appendFormat:@" %02x", c];
//	}
//	NSLog(@"%@", desc);
//}

- (void)onVideoFrame:(NSData *)nalu pts:(double)pts{
//	NSLog(@"pts: %.3f", pts);
	if(!_videoClip){
		_videoClip = [[VideoClip alloc] init];
		_videoClip.sps = _videoEncoder.sps;
		_videoClip.pps = _videoEncoder.pps;
	}

//	UInt8 *p = (UInt8 *)nalu.bytes;
//	int type = p[4] & 0x1f;
//	NSLog(@"NALU Type \"%d\"", type);
	
	[_videoClip appendFrame:nalu pts:pts];

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
//		// TODO: 模拟设备丢包
//		static int i = 0;
//		if(i++ % 10 == 9){
//			return;
//		}
		[_audioEncoder encodeSampleBuffer:sampleBuffer];
	}
	if(captureOutput == _videoDataOutput){
		[_videoEncoder encodeSampleBuffer:sampleBuffer];
	}
}

@end
