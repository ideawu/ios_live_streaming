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

- (void)start:(void (^)(NSData *nalu, double pts, double duration))callback{
	_callback = callback;
}

- (void)createSession{
	if(_session){
		[self shutdown];
	}

#if !TARGET_OS_MAC
	NSDictionary *params = nil;
	NSDictionary *pixelBufferAttrs = nil;
#else
	NSDictionary *params = @{
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

- (NSData *)buildAVCC:(const UInt8 *)data length:(int)len{
	NSMutableData *ret = [[NSMutableData alloc] initWithCapacity:4 + len];
	UInt32 bigendian_len = htonl(len);
	[ret appendBytes:&bigendian_len length:4];
	[ret appendBytes:data length:len];
	return ret;
}

- (void)onCodecCallback:(CMSampleBufferRef)sampleBuffer{
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

//			_sps = [NSData dataWithBytes:sps length:sps_size];
//			_pps = [NSData dataWithBytes:pps length:pps_size];
			_sps = [self buildAVCC:sps length:(int)sps_size];
			_pps = [self buildAVCC:pps length:(int)pps_size];

			log_debug(@"sps(%d): %@", (int)sps_size, _sps);
			log_debug(@"pps(%d): %@", (int)pps_size, _pps);
		}
	}

	char *buf;
	size_t size;
	CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
	CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &size, &buf);

	if(_callback){
		// 1 sample buffer contains multiple NALUs in AVCC format
		// http://stackoverflow.com/questions/28396622/extracting-h264-from-cmblockbuffer
//		NSData *data = [NSData dataWithBytes:buf length:size];
		
		NSMutableData *data = [[NSMutableData alloc] initWithCapacity:size];
		[data appendBytes:"0000" length:4]; // the len
		
		UInt8 *p = (UInt8 *)buf;
		while(p < (UInt8 *)buf + size){
//			log_debug(@"%02x %02x %02x %02x", (UInt8)p[0], (UInt8)p[1], (UInt8)p[2], (UInt8)p[3]);
			uint32_t len = (p[0]<<24) + (p[1]<<16) + (p[2]<<8) + p[3];
			UInt8 *nalu = p + 4;
			p += 4 + len;

			int type = nalu[0] & 0x1f;
//			NSLog(@"NALU Type \"%d\", len: %u", type, len);
			if(type == 6){
				// just drop SEI?
				//log_debug(@"%@", [NSData dataWithBytes:nalu length:len]);
			}else{
				[data appendBytes:nalu length:len];
			}
		}
		
		UInt32 len = ntohl(data.length - 4);
		[data replaceBytesInRange:NSMakeRange(0, 4) withBytes:&len];
		
//		log_debug(@"%d", (int)size);
		_callback(data, pts, duration);
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
	if(!_session){
		[self createSessionFromSampleBuffer:sampleBuffer];
	}

	CMTime pts = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
	CMTime duration = CMSampleBufferGetOutputDuration(sampleBuffer);
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
