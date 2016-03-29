//
//  VideoDecoder.m
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "VideoDecoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface VideoDecoder(){
	void (^_callback)(CVPixelBufferRef pixelBuffer, double pts, double duration);
}
@property (nonatomic, assign) VTDecompressionSessionRef session;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@end


@implementation VideoDecoder

- (id)init{
	self = [super init];
	_callback = NULL;
	_session = NULL;
	_formatDesc = NULL;
	return self;
}

- (void)dealloc{
	[self shutdown];
}

- (void)shutdown{
	if(_session){
		VTDecompressionSessionInvalidate(_session);
		CFRelease(_session);
		_session = NULL;
	}
	if(_formatDesc){
		CFRelease(_formatDesc);
		_formatDesc = NULL;
	}
}

- (BOOL)isReadyForFrame{
	return _session != NULL;
}

- (void)start:(void (^)(CVPixelBufferRef pixelBuffer, double pts, double duration))callback{
	_callback = callback;
}

- (void)setSps:(NSData *)sps pps:(NSData *)pps{
	if(_formatDesc){
		CFRelease(_formatDesc);
	}
	// no start code
	uint8_t*  arr[2] = {(uint8_t*)sps.bytes, (uint8_t*)pps.bytes};
	size_t sizes[2] = {sps.length, sps.length};
	
	OSStatus err;
	err = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
																 (const uint8_t *const*)arr,
																 sizes, 4,
																 &_formatDesc);
	if(err != noErr) log_debug(@"Create Format Description ERROR: %d", (int)err);
	
	[self createSession];
}

- (void)createSession{
	if(_session){
		[self shutdown];
	}

	VTDecompressionOutputCallbackRecord callBackRecord;
	callBackRecord.decompressionOutputCallback = decompressCallback;
	callBackRecord.decompressionOutputRefCon = (__bridge void *)self;

	// you can set some desired attributes for the destination pixel buffer.  I didn't use this but you may
	// if you need to set some attributes, be sure to uncomment the dictionary in VTDecompressionSessionCreate
#if TARGET_OS_IPHONE
	NSDictionary *decoderParameters = @{
										(id)kVTDecompressionPropertyKey_RealTime: @(YES),
										};
	NSDictionary *pixelBufferAttrs = @{
									   (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
									   (id)kCVPixelBufferOpenGLESCompatibilityKey: @(YES),
									   };
#else
	NSDictionary *decoderParameters = nil;
	NSDictionary *pixelBufferAttrs = @{
									   (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
									   //(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange), // 据说更快, 但导致转img出错
									   };
#endif
	OSStatus status =  VTDecompressionSessionCreate(NULL, _formatDesc,
													(__bridge CFDictionaryRef)(decoderParameters),
													(__bridge CFDictionaryRef)(pixelBufferAttrs),
													&callBackRecord, &_session);
	if(status != noErr) log_debug(@"\t\t VTD ERROR type: %d", (int)status);
	log_debug(@"decode session created");
}

// VTDecompressionOutputCallback
static void decompressCallback(void *decompressionOutputRefCon,
							void *sourceFrameRefCon,
							OSStatus err,
							VTDecodeInfoFlags infoFlags,
							CVImageBufferRef imageBuffer,
							CMTime pts,
							CMTime duration){
	if(err != noErr){
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"Decompressed error: %@", error);
		return;
	}
	VideoDecoder *me = (__bridge VideoDecoder *)decompressionOutputRefCon;
	[me onCodecCallback:imageBuffer pts:CMTimeGetSeconds(pts) duration:CMTimeGetSeconds(duration)];
}

- (void)onCodecCallback:(CVImageBufferRef)imageBuffer pts:(double)pts duration:(double)duration{
	LOG_FIRST_RUN();
	if(_callback){
		_callback(imageBuffer, pts, duration);
	}
}

- (void)decode:(NSData *)frame{
	return [self decode:frame pts:0 duration:0];
}

- (void)decode:(NSData *)frame pts:(double)pts{
	return [self decode:frame pts:pts duration:0];
}

- (void)decode:(NSData *)frame pts:(double)pts duration:(double)duration{
	LOG_FIRST_RUN();
	// BOOL needNewSession = (VTDecompressionSessionCanAcceptFormatDescription(session, formatDesc2) == false);
	CMSampleBufferRef sampleBuffer = [self createSampleBufferFromFrame:frame pts:pts duration:duration];
	if(sampleBuffer){
		// 不能异步, 否则会乱序
		//VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
		VTDecodeFrameFlags flags = 0;
		VTDecodeInfoFlags flagOut;
		//log_debug(@"sampleBuffer: %d", (int)CFGetRetainCount(sampleBuffer));
		// decode 接受的1帧, 可以分隔多个NALU, AVCC 格式
		VTDecompressionSessionDecodeFrame(_session, sampleBuffer, flags, NULL, &flagOut);
		CFRelease(sampleBuffer);
	}
}

- (CMSampleBufferRef)createSampleBufferFromFrame:(NSData *)frame pts:(double)pts duration:(double)duration{
	CMSampleBufferRef sampleBuffer = NULL;
	CMBlockBufferRef blockBuffer = NULL;
	size_t length = frame.length;
	OSStatus err;
	err = CMBlockBufferCreateWithMemoryBlock(NULL,
											 NULL,
											 length,
											 kCFAllocatorDefault,
											 NULL,
											 0,
											 length,
											 kCMBlockBufferAssureMemoryNowFlag,
											 &blockBuffer);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
	}else{
		err = CMBlockBufferReplaceDataBytes(frame.bytes, blockBuffer, 0, length);
	}
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
	}else{
		CMSampleTimingInfo time;
		time.presentationTimeStamp = CMTimeMakeWithSeconds(pts, 60000);
		time.duration = CMTimeMakeWithSeconds(duration, 60000);
		err = CMSampleBufferCreate(kCFAllocatorDefault,
								   blockBuffer,
								   true, NULL, NULL,
								   _formatDesc,
								   1, // num samples
								   1, &time,
								   1, &length,
								   &sampleBuffer);
	}
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		log_debug(@"error: %@", error);
	}

	if(blockBuffer){
		CFRelease(blockBuffer);
	}

	return sampleBuffer;
}

@end
