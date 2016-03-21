//
//  LiveCapture.m
//  irtc
//
//  Created by ideawu on 3/15/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "LiveCapture.h"

@interface LiveCapture ()<AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>{
	AVCaptureDeviceInput *_audioInput;
	AVCaptureDeviceInput *_videoInput;
	AVCaptureAudioDataOutput* _audioDataOutput;
	AVCaptureVideoDataOutput* _videoDataOutput;
	
	dispatch_queue_t _captureQueue;

	void (^_audioCallback)(CMSampleBufferRef sampleBuffer);
	void (^_videoCallback)(CMSampleBufferRef sampleBuffer);

	double _lastVideoPTS;
}
@property (nonatomic) AVCaptureDevice *audioDevice;
@property (nonatomic) AVCaptureDevice *videoDevice;
@end

@implementation LiveCapture

- (id)init{
	self = [super init];
	_lastVideoPTS = 0;
	_captureQueue = nil;
	_session = [[AVCaptureSession alloc] init];
	[_session setSessionPreset:AVCaptureSessionPreset640x480];
	_captureQueue = dispatch_queue_create("capture", DISPATCH_QUEUE_SERIAL);
	return self;
}

- (void)start{
	[_session startRunning];
}

- (void)stop{
	[_session stopRunning];
}

- (void)setupAudio:(void (^)(CMSampleBufferRef sampleBuffer))callback{
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
	
	if(!_audioDataOutput || !_audioInput){
		log_error(@"init audio device failed!");
		return;
	}
	
	[_session beginConfiguration];
	[_session addOutput:_audioDataOutput];
	[_session addInput:_audioInput];
	[_session commitConfiguration];
}

- (void)setupVideo:(void (^)(CMSampleBufferRef sampleBuffer))callback{
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
	
	if(!_videoDataOutput || !_videoInput){
		log_error(@"init video device failed!");
		return;
	}

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
		[connection setVideoOrientation:orientation];
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
		if(_audioCallback){
			_audioCallback(sampleBuffer);
		}
	}
	if(captureOutput == _videoDataOutput){
		double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
		double duration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer));

		// iOS 7.0
		if(isnan(duration)){
			if(_lastVideoPTS != 0){
				duration = pts - _lastVideoPTS;
				//log_debug(@"pts: %f, duration: %f", pts, duration);

				CMSampleTimingInfo time;
				time.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
				time.duration = CMTimeMakeWithSeconds(duration, 10000000);

				CMSampleBufferRef newSampleBuffer;
				CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
													  sampleBuffer,
													  1,
													  &time,
													  &newSampleBuffer);
				if(_videoCallback){
					_videoCallback(newSampleBuffer);
				}
				CFRelease(newSampleBuffer);
			}
		}else{
			if(_videoCallback){
				_videoCallback(sampleBuffer);
			}
		}
		_lastVideoPTS = pts;
	}
}

@end
