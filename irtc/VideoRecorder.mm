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

	double _pts_start;
	double _pts_end;
}
@property (nonatomic) int fps;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) AVEncoder* encoder;
@property (nonatomic) NSData *naluStartCode;
@property (nonatomic) NSMutableData *videoSPSandPPS;
@property (nonatomic) NSMutableArray *frames;
@end

@implementation VideoRecorder

- (id)init{
	self = [super init];
	_fps = 30; // 需要在设备初始化之后更新为实际的值
	_width = 360;
	_height = 480;
	_frames = [[NSMutableArray alloc] init];
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

- (void) initializeNALUnitStartCode {
	char codes[4];
	codes[0] = 0x00;
	codes[1] = 0x00;
	codes[2] = 0x00;
	codes[3] = 0x01;
	_naluStartCode = [NSData dataWithBytes:codes length:4];
}

- (void)start{
	[self initializeNALUnitStartCode];

	_encoder = [AVEncoder encoderForHeight:_height andWidth:_width bitrate:100*1024];
	[_encoder encodeWithBlock:^int(NSArray *frames, double pts) {
		[self processFrames:frames pts:pts];
		return 0;
	} onParams:^int(NSData *params) {
		NSLog(@"params: %@", params);
		[self generateSPSandPPS];
		return 0;
	}];

	[_session startRunning];
}

- (void)generateSPSandPPS {
	NSData* config = _encoder.getConfigData;
	if (!config) {
		return;
	}
	avcCHeader avcC((const BYTE*)[config bytes], (int)[config length]);
	SeqParamSet seqParams;
	seqParams.Parse(avcC.sps());

	NSData* spsData = [NSData dataWithBytes:avcC.sps()->Start() length:avcC.sps()->Length()];
	NSData *ppsData = [NSData dataWithBytes:avcC.pps()->Start() length:avcC.pps()->Length()];

	_videoSPSandPPS = [NSMutableData dataWithCapacity:avcC.sps()->Length() + avcC.pps()->Length() + _naluStartCode.length * 2];
	[_videoSPSandPPS appendData:_naluStartCode];
	[_videoSPSandPPS appendData:spsData];
	[_videoSPSandPPS appendData:_naluStartCode];
	[_videoSPSandPPS appendData:ppsData];
	NSLog(@"_videoSPSandPPS: %@", _videoSPSandPPS);
}

- (void)processFrames:(NSArray *)frames pts:(double)pts{
	//NSLog(@"pts: %f", pts);
	if(_frames.count == 0){
		_pts_start = pts;
	}
	[_frames addObjectsFromArray:frames];
	_pts_end = pts;

	// 根据时间, 计算出 chunk 应该包含的帧数
	double chunk_duration = 0.3;
	if(_pts_end - _pts_start > chunk_duration){
		NSMutableData *bytes = [NSMutableData data];
		NSData *sei = nil; // Supplemental enhancement information
		BOOL hasKeyframe = NO;
		for (NSData *data in _frames) {
			unsigned char* pNal = (unsigned char*)[data bytes];
			int nal_ref_bit = pNal[0] & 0x60;
			int nal_type = pNal[0] & 0x1f;
			if (nal_ref_bit == 0 && nal_type == 6) { // SEI
				sei = data;
				continue;
			} else if (nal_type == 5) { // IDR
				hasKeyframe = YES;
				[bytes appendData:_videoSPSandPPS];
				if (sei) {
					[self appendNALUWithFrame:sei toData:bytes];
					sei = nil;
				}
				[self appendNALUWithFrame:data toData:bytes];
			} else {
				[self appendNALUWithFrame:data toData:bytes];
			}
		}
		NSLog(@"%2d frames[%.3f ~ %.3f] to send, %5d bytes, has_key_frame: %@", (int)_frames.count, _pts_start, _pts_end, (int)bytes.length, hasKeyframe?@"yes":@"no");
		[_frames removeAllObjects];
	}
}

- (void)appendNALUWithFrame:(NSData *)frame toData:(NSMutableData *)data{
	[data appendData:_naluStartCode];
	[data appendData:frame];
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
