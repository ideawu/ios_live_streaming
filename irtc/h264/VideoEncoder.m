//
//  VideoEncoder.m
//  irtc
//
//  Created by ideawu on 16-3-13.
//  Copyright (c) 2016年 ideawu. All rights reserved.
//

#import "VideoEncoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface VideoEncoder(){
	void (^_callback)(NSData *h264, double pts, double duration);
}
@property (nonatomic, assign) VTCompressionSessionRef session;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic) int width;
@property (nonatomic) int height;
@end


@implementation VideoEncoder

- (id)init{
	self = [super init];
	_width = 360;
	_height = 480;
	return self;
}

- (void)dealloc{
	[self shutdown];
}

- (void)shutdown{
	if(_session){
		VTCompressionSessionInvalidate(_session);
		CFRelease(_session);
		_session = NULL;
	}
}

- (void)start:(void (^)(NSData *h264, double pts, double duration))callback{
	_callback = callback;
}

- (void)createSession{
	if(_session){
		[self shutdown];
	}

	OSStatus err;
	err = VTCompressionSessionCreate(NULL,
									 _width,
									 _height,
									 kCMVideoCodecType_H264,
									 NULL,
									 NULL,
									 NULL,
									 compressCallback,
									 (__bridge void *)self,
									 &_session);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
		return;
	}
	// kVTCompressionPropertyKey_AverageBitRate
	// kVTCompressionPropertyKey_DataRateLimits
	log_debug(@"encode session created, width: %d, height: %d", _width, _height);
}

- (void)createSessionFromSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	_width = (int)CVPixelBufferGetWidth(imageBuffer);
	_height = (int)CVPixelBufferGetHeight(imageBuffer);
	[self createSession];
}

// VTCompressionOutputCallback
static void compressCallback(
					  void *outputCallbackRefCon,
					  void *sourceFrameRefCon,
					  OSStatus status,
					  VTEncodeInfoFlags infoFlags,
					  CMSampleBufferRef sampleBuffer){
//	char *src;
//	size_t src_size;
//	CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(sourceFrameRefCon), 0, NULL, &src_size, &src);
//	char *dst;
//	size_t dst_size;
//	CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(sampleBuffer), 0, NULL, &dst_size, &dst);
//	log_debug(@"compress %d => %d", (int)src_size, (int)dst_size);

	VideoEncoder *me = (__bridge VideoEncoder *)outputCallbackRefCon;
	[me onCodecCallback:sampleBuffer];
}

- (void)onCodecCallback:(CMSampleBufferRef)sampleBuffer{
	if(!sampleBuffer){
		log_debug(@"sample buffer dropped");
		return;
	}
	
	double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	double dts = CMTimeGetSeconds(CMSampleBufferGetDecodeTimeStamp(sampleBuffer));
	double duration = CMTimeGetSeconds(CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer));
//	log_debug(@"encoded pts: %f, duration: %f, dts: %f", pts, duration, dts);

	//printf("status: %d\n", (int) status);
	if(!_sps){
		bool isKeyframe = false;
		CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
		if(attachments != NULL) {
			CFDictionaryRef attachment;
			CFBooleanRef dependsOnOthers;
			attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
			dependsOnOthers = (CFBooleanRef)CFDictionaryGetValue(attachment, kCMSampleAttachmentKey_DependsOnOthers);
			isKeyframe = (dependsOnOthers == kCFBooleanFalse);
		}

		if(isKeyframe) {
			CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
			size_t sps_size, pps_size;
			const uint8_t* sps, *pps;

			// get sps/pps without start code
			CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &sps_size, NULL, NULL);
			CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &pps_size, NULL, NULL);

			_sps = [NSData dataWithBytes:sps length:sps_size];
			_pps = [NSData dataWithBytes:pps length:pps_size];

			log_debug(@"sps(%d): %@", (int)sps_size, _sps);
			log_debug(@"pps(%d): %@", (int)pps_size, _pps);
		}
	}

	char *buf;
	size_t size;
	CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
	CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &size, &buf);

	if(_callback){
		NSData *data = [NSData dataWithBytes:buf length:size];
		_callback(data, pts, duration);
	}
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	if(!_session){
		[self createSessionFromSampleBuffer:sampleBuffer];
	}

	CMTime pts = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
	CMTime duration = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
//	double dts = CMTimeGetSeconds(CMSampleBufferGetDecodeTimeStamp(sampleBuffer));
//	log_debug(@"encoding pts: %f, duration: %f, dts: %f", CMTimeGetSeconds(pts), CMTimeGetSeconds(duration), dts);

	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

	NSDictionary *properties = nil;
//	BOOL forceKeyFrame = NO;
//	if(forceKeyFrame){
//		properties = @{
//					   (id)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES
//					   };
//	}
	OSStatus err = VTCompressionSessionEncodeFrame(_session,
												   imageBuffer,
												   pts,
												   duration,
												   (__bridge CFDictionaryRef)properties,
												   imageBuffer,
												   NULL);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
		return;
	}
}

@end
