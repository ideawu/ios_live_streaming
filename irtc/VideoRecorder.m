//
//  VideoRecorder.m
//  irtc
//
//  Created by ideawu on 3/4/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoRecorder.h"
#import "AVEncoder.h"

@interface VideoRecorder()<AVCaptureVideoDataOutputSampleBufferDelegate>{
	AVCaptureDevice *videoDevice;
	AVCaptureDeviceInput *videoInput;
	AVCaptureVideoDataOutput* _videoDataOutput;
	
	dispatch_queue_t _captureQueue;
	dispatch_queue_t _processQueue;
}
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic, strong) AVEncoder* encoder;
@property (nonatomic, strong) NSData *naluStartCode;
@property (nonatomic, strong) NSMutableData *videoSPSandPPS;
@property (nonatomic, strong) NSMutableArray *orphanedFrames;
@property (nonatomic, strong) NSMutableArray *orphanedSEIFrames;
@property (nonatomic) CMTime lastPTS;
@end

@implementation VideoRecorder

- (id)init{
	self = [super init];
	_width = 360;
	_height = 480;
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
		float setFPS = 30.0;
		if(range.minFrameRate <= setFPS && range.maxFrameRate >= setFPS){
			if([videoDevice lockForConfiguration:nil]){
				videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, setFPS);
				videoDevice.activeVideoMaxFrameDuration = CMTimeMake(1, setFPS);
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

- (void) initializeNALUnitStartCode {
	NSUInteger naluLength = 4;
	uint8_t *nalu = (uint8_t*)malloc(naluLength * sizeof(uint8_t));
	nalu[0] = 0x00;
	nalu[1] = 0x00;
	nalu[2] = 0x00;
	nalu[3] = 0x01;
	_naluStartCode = [NSData dataWithBytesNoCopy:nalu length:naluLength freeWhenDone:YES];
}

- (void)start{
	[self initializeNALUnitStartCode];
	_lastPTS = kCMTimeInvalid;
	_orphanedFrames = [NSMutableArray arrayWithCapacity:2];
	_orphanedSEIFrames = [NSMutableArray arrayWithCapacity:2];
	
	_encoder = [AVEncoder encoderForHeight:_height andWidth:_width];
	[_encoder encodeWithBlock:^int(NSArray *frames, double pts) {
		[self processFrames:frames];
		return 0;
	} onParams:^int(NSData *params) {
		NSLog(@"params: %@", params);
		return 0;
	}];

	[_session startRunning];
}

- (void)processFrames:(NSArray *)frames{
	NSLog(@"%d frames ready", (int)frames.count);

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
