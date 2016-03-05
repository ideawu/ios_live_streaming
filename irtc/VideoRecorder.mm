//
//  VideoRecorder.m
//  irtc
//
//  Created by ideawu on 3/4/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoRecorder.h"
#import "AVEncoder.h"
#import "VideoClip.h"

@interface VideoRecorder()<AVCaptureVideoDataOutputSampleBufferDelegate>{
	AVCaptureDevice *videoDevice;
	AVCaptureDeviceInput *videoInput;
	AVCaptureVideoDataOutput* _videoDataOutput;
	
	dispatch_queue_t _captureQueue;
	dispatch_queue_t _processQueue;

	double _pts_start;
	double _pts_end;
	
	VideoClip *_clip;
}
@property (nonatomic) int fps;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) AVEncoder* encoder;
@end

@implementation VideoRecorder

- (id)init{
	self = [super init];
	_fps = 30; // 需要在设备初始化之后更新为实际的值
	_width = 360;
	_height = 480;
	_clip = [[VideoClip alloc] init];
	[self setupDevices];
	return self;
}

- (void)setupDevices{
	NSError *error = nil;
	_captureQueue = dispatch_queue_create("capture", DISPATCH_QUEUE_SERIAL);
	_processQueue = dispatch_queue_create("process", DISPATCH_QUEUE_SERIAL);
	
	_session = [[AVCaptureSession alloc] init];
	
	videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	for(AVCaptureDevice *dev in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]){
		if(dev.position == AVCaptureDevicePositionFront){
			videoDevice = dev;
			break;
		}
	}
	videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	
	for(AVFrameRateRange *range in videoDevice.activeFormat.videoSupportedFrameRateRanges){
		if(range.minFrameRate <= _fps && range.maxFrameRate >= _fps){
			if([videoDevice lockForConfiguration:nil]){
				videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, _fps);
				videoDevice.activeVideoMaxFrameDuration = CMTimeMake(1, _fps);
				[videoDevice unlockForConfiguration];
				break;
			}
		}
	}

	_videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	[_videoDataOutput setSampleBufferDelegate:self queue:_captureQueue];
	NSDictionary* settings = @{
							   (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
							   };
	_videoDataOutput.videoSettings = settings;
	
	[_session beginConfiguration];
	[_session setSessionPreset:AVCaptureSessionPresetMedium];
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

- (void)start{
	_encoder = [AVEncoder encoderForHeight:_height andWidth:_width bitrate:100*1024];
	[_encoder encodeWithBlock:^int(NSArray *frames, double pts) {
		[self processFrames:frames pts:pts];
		return 0;
	} onParams:^int(NSData *params) {
		[self processParams:params];
		return 0;
	}];

	[_session startRunning];
}

- (void)processParams:(NSData *)params{
	NSLog(@"params: %@", params);
	avcCHeader avcC((const BYTE*)[params bytes], (int)[params length]);
	//	SeqParamSet seqParams;
	//	seqParams.Parse(avcC.sps());
	_clip.sps = [NSData dataWithBytes:avcC.sps()->Start() length:avcC.sps()->Length()];
	_clip.pps = [NSData dataWithBytes:avcC.pps()->Start() length:avcC.pps()->Length()];
	
	NSMutableString *desc = [[NSMutableString alloc] init];
	[desc appendString:@"sps:"];
	for(int i=0; i<_clip.sps.length; i++){
		unsigned char c = ((const unsigned char *)_clip.sps.bytes)[i];
		[desc appendFormat:@" %02x", c];
	}
	[desc appendString:@" pps:"];
	for(int i=0; i<_clip.pps.length; i++){
		unsigned char c = ((const unsigned char *)_clip.pps.bytes)[i];
		[desc appendFormat:@" %02x", c];
	}
	NSLog(@"%@", desc);
}

- (void)processFrames:(NSArray *)frames pts:(double)pts{
	for (NSData *data in frames){
		[_clip appendFrame:data pts:pts];
	}

	double max_chunk_duration = 0.3;
	if(_clip.duration >= max_chunk_duration){
		NSData *data = _clip.data;
		NSLog(@"%2d frames[%.3f ~ %.3f] to send, %5d bytes, has_i_frame: %@",
			  _clip.frameCount, _clip.startTime, _clip.endTime, (int)data.length,
			  _clip.hasIFrame?@"yes":@"no");
		
		VideoClip *c = [VideoClip clipFromData:data];
		
		[_clip reset];
	}
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

// TODO: 如果能保证正确性, 可以改为 NO, 提高性能
- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput{
	return YES;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
	[_encoder encodeFrame:sampleBuffer];
}


@end
