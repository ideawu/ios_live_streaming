//
//  LiveRecorder.m
//  irtc
//
//  Created by ideawu on 3/9/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "VideoClip.h"
#import "LiveRecorder.h"
#import "AudioEncoder.h"
#import "VideoEncoder.h"
#import "VideoReader.h"
#import "LiveCapture.h"
#import "MP4FileVideoEncoder.h"

@interface LiveRecorder(){
	VideoClip *_videoClip;
}
@property (nonatomic, copy) void (^audioCallback)(NSData *data, double pts, double duration);
@property (nonatomic, copy) void (^videoCallback)(VideoClip *clip);

@property (nonatomic) LiveCapture *capture;
@property (nonatomic) VideoEncoder *videoEncoder;
@property (nonatomic) AudioEncoder *audioEncoder;

@end


@implementation LiveRecorder

- (id)init{
	self = [super init];
	_clipDuration = 0.3;
	_capture = [[LiveCapture alloc] init];
	return self;
}

- (AVCaptureSession *)session{
	return _capture.session;
}

- (void)start{
	[_capture start];
}

- (void)stop{
	[_capture stop];
}

- (void)setupAudio:(void (^)(NSData *data, double pts, double duration))callback{
	__weak typeof(self) me = self;
	_audioCallback = callback;
	[_capture setupAudio:^(CMSampleBufferRef sampleBuffer) {
		[me onAudioCapturedSampleBuffer:sampleBuffer];
	}];
	
	_audioEncoder = [[AudioEncoder alloc] init];
	[_audioEncoder start:^(NSData *frame, double pts, double duration) {
		[me onAudioEncodedFrame:frame pts:pts duration:duration];
	}];
}

- (void)setupVideo:(void (^)(VideoClip *clip))callback{
	__weak typeof(self) me = self;
	_videoCallback = callback;
	[_capture setupVideo:^(CMSampleBufferRef sampleBuffer) {
		[me onVideoCapturedSampleBuffer:sampleBuffer];
	}];

	BOOL use_file_encoder = NO;

#if TARGET_OS_IPHONE
	if([UIDevice currentDevice].systemVersion.floatValue < 8.0){
		use_file_encoder = YES;
	}
#else
	// not working on macOS 10.13.1
//	use_file_encoder = YES;
#endif

	if(use_file_encoder){
		log_debug(@"use file encoder");
		_videoEncoder = (VideoEncoder *)[[MP4FileVideoEncoder alloc] init];
	}else{
		log_debug(@"use hardware encoder");
		_videoEncoder = [[VideoEncoder alloc] init];
	}
	if(_width > 0){
		_videoEncoder.width = _width;
	}
	if(_height > 0){
		_videoEncoder.height = _height;
	}
	_width = _videoEncoder.width;
	_height = _videoEncoder.height;
	
	[_videoEncoder start:^(NSData *frame, double pts, double duration) {
		//log_debug(@"encoded, pts: %f, duration: %f, %d bytes", pts, duration, (int)frame.length);
		[me onVideoEncodedFrame:frame pts:pts duration:duration];
	}];
}

#pragma mark - Capture callbacks

- (void)onAudioCapturedSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[_audioEncoder encodeSampleBuffer:sampleBuffer];
}

- (void)onVideoCapturedSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	[_videoEncoder encodeSampleBuffer:sampleBuffer];
}

#pragma mark - Encoder callbacks

- (void)onAudioEncodedFrame:(NSData *)frame pts:(double)pts duration:(double)duration{
	// TODO: build AudioClip
	_audioCallback(frame, pts, duration);
}

- (void)onVideoEncodedFrame:(NSData *)frame pts:(double)pts duration:(double)duration{
//	log_debug(@"pts: %.3f", pts);
	if(!_videoClip){
		_videoClip = [[VideoClip alloc] init];
		_videoClip.sps = _videoEncoder.sps;
		_videoClip.pps = _videoEncoder.pps;
	}

	UInt8 *p = (UInt8 *)frame.bytes;
	int type = p[4] & 0x1f;
//	log_debug(@"NALU Type \"%d\"", type);
	
	[_videoClip appendFrame:frame pts:pts];

	if(_videoClip.duration >= _clipDuration && type == 1){
		_videoCallback(_videoClip);
		_videoClip = nil;
	}
}

@end
