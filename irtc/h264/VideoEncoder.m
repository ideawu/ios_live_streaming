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
	void (^_callback)(NSData *frame, double pts, double duration);
}
@property (nonatomic, assign) VTCompressionSessionRef session;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@end


@implementation VideoEncoder

- (id)init{
	self = [super init];
	_width = 480;
	_height = 640;
	return self;
}

- (void)dealloc{
	[self shutdown];
}

- (void)start:(void (^)(NSData *frame, double pts, double duration))callback{
	_callback = callback;
}

- (void)shutdown{
	if(_session){
		VTCompressionSessionInvalidate(_session);
		CFRelease(_session);
		_session = NULL;
	}
}

- (void)createSession{
	if(_session){
		[self shutdown];
	}

#if TARGET_OS_IPHONE
	NSDictionary *params = nil;
	NSDictionary *pixelBufferAttrs = @{
									   (id)kCVPixelBufferOpenGLESCompatibilityKey: @YES
									   };
#else
	// 似乎无论如何, Mac 也不能使用硬件加速. 但 AVFoundation 是可以的. 为什么?
	NSDictionary *params = @{
//							 (id)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES,
//							 (id)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @YES,
//							 (id)kVTVideoEncoderSpecification_EncoderID: @"com.apple.videotoolbox.videoencoder.h264.gva",
//							 (id)kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder: @YES,
//							 (id)kVTCompressionPropertyKey_RealTime: @YES,
							 };
	NSDictionary *pixelBufferAttrs = nil;
#endif
/*
 kVTCompressionPropertyKey_AllowFrameReordering
 kVTCompressionPropertyKey_AverageBitRate
 kVTCompressionPropertyKey_H264EntropyMode
 kVTH264EntropyMode_CAVLC/kVTH264EntropyMode_CABAC
 kVTCompressionPropertyKey_RealTime
 kVTCompressionPropertyKey_ProfileLevel
 for example: kVTProfileLevel_H264_Main_AutoLevel
 // kVTCompressionPropertyKey_AverageBitRate
	// kVTCompressionPropertyKey_DataRateLimits
*/
	OSStatus err;
	err = VTCompressionSessionCreate(NULL,
									 _width,
									 _height,
									 kCMVideoCodecType_H264,
									 (__bridge CFDictionaryRef)(params),
									 (__bridge CFDictionaryRef)(pixelBufferAttrs),
									 NULL,
									 compressCallback,
									 (__bridge void *)self,
									 &_session);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
		return;
	}
	VTCompressionSessionPrepareToEncodeFrames(_session);
	log_debug(@"encode session created, width: %d, height: %d", _width, _height);
	
	//	{
	//		CFArrayRef arr;
	//		OSStatus err = VTCopyVideoEncoderList(NULL, &arr);
	//		log_debug(@"%d %@", err, arr);
	//		CFRelease(arr);
	//		//exit(0);
	//	}
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
					  OSStatus err,
					  VTEncodeInfoFlags infoFlags,
					  CMSampleBufferRef sampleBuffer){
//	char *src;
//	size_t src_size;
//	CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(sourceFrameRefCon), 0, NULL, &src_size, &src);
//	char *dst;
//	size_t dst_size;
//	CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(sampleBuffer), 0, NULL, &dst_size, &dst);
//	log_debug(@"compress %d => %d", (int)src_size, (int)dst_size);

	if(err != noErr){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
	}else{
		VideoEncoder *me = (__bridge VideoEncoder *)outputCallbackRefCon;
		[me onCodecCallback:sampleBuffer];
	}
}

- (void)onCodecCallback:(CMSampleBufferRef)sampleBuffer{
	LOG_FIRST_RUN();
	if(!sampleBuffer){
		log_debug(@"sample buffer dropped");
		return;
	}
	
	double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
	double duration = CMTimeGetSeconds(CMSampleBufferGetOutputDuration(sampleBuffer));
//	double dts = CMTimeGetSeconds(CMSampleBufferGetDecodeTimeStamp(sampleBuffer));
//	log_debug(@"encoded pts: %f, duration: %f, dts: %f", pts, duration, dts);

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

	UInt8 *buf;
	size_t size;
	CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
	CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &size, (char **)&buf);

	if(_callback){
		// strip leading SEIs
		while(size > 0){
			uint32_t len = (buf[0]<<24) + (buf[1]<<16) + (buf[2]<<8) + buf[3];
			int type = buf[4] & 0x1f;
			if(type == 6){ // SEI
				buf += 4 + len;
				size -= 4 + len;
			}else{
				break;
			}
		}
		if(size >= 5){
			NSData *data = [NSData dataWithBytes:buf length:size];
			_callback(data, pts, duration);
		}
	}
}

//- (void)encode:(NSData *)frame{
//	return [self encode:frame pts:0 duration:0];
//}
//
//- (void)encode:(NSData *)frame pts:(double)pts{
//	return [self encode:frame pts:0 duration:0];
//}
//
//- (void)encode:(NSData *)frame pts:(double)pts duration:(double)duration{
//	// TODO: 如何创建 sample buffer?
//}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	LOG_FIRST_RUN();
	if(!_session){
		[self createSessionFromSampleBuffer:sampleBuffer];
	}
	
	CMTime pts = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
	CMTime duration = CMSampleBufferGetOutputDuration(sampleBuffer);
//	double dts = CMTimeGetSeconds(CMSampleBufferGetDecodeTimeStamp(sampleBuffer));
//	log_debug(@"encoding pts: %f, duration: %f, dts: %f", CMTimeGetSeconds(pts), CMTimeGetSeconds(duration), dts);

	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//	log_debug(@"width: %d, height: %d, %d bytes",
//			  (int)CVPixelBufferGetWidth(imageBuffer),
//			  (int)CVPixelBufferGetHeight(imageBuffer),
//			  (int)CVPixelBufferGetDataSize(imageBuffer)
//			  );
	
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
	VTCompressionSessionCompleteFrames(_session, kCMTimeInvalid);
}

- (void)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer pts:(double)pts duration:(double)duration{
	OSStatus err;
	CMSampleBufferRef sampleBuffer = NULL;
	CMVideoFormatDescriptionRef videoInfo = NULL;
	
	err = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
	if(!err){
		CMSampleTimingInfo time;
		time.presentationTimeStamp = CMTimeMakeWithSeconds(pts, 60000);
		time.duration = CMTimeMakeWithSeconds(duration, 60000);
		err = CMSampleBufferCreateForImageBuffer(NULL,
												 pixelBuffer, true, NULL, NULL,
												 videoInfo,
												 &time,
												 &sampleBuffer);
	}
	if(!err){
		[self encodeSampleBuffer:sampleBuffer];
	}
	
	if(videoInfo){
		CFRelease(videoInfo);
	}
	if(sampleBuffer){
		CFRelease(sampleBuffer);
	}
}

@end
